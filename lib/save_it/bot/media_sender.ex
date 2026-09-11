defmodule SaveIt.Bot.MediaSender do
  @moduledoc false

  require Logger

  import SaveIt.Bot.MapHelper, only: [put_optional: 3, put_optional_keyword: 3]

  alias SaveIt.AnimationUpload
  alias SaveIt.Bot.FileType
  alias SaveIt.Bot.LogFormat
  alias SaveIt.Bot.MessageInfo
  alias SaveIt.Bot.PhotoIndex
  alias SaveIt.Bot.ThumbnailDownload
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  alias SaveIt.IndexImage
  alias SaveIt.Telegram
  alias SaveIt.VideoUpload
  alias SmallSdk.Telegram, as: TelegramClient

  @telegram_upload_max_file_size 50 * 1024 * 1024
  @telegram_file_too_large_message "💔 File is too large for Telegram Bot API upload."
  @telegram_video_too_large_thumbnail_message "Video downloaded; Telegram upload was too large."

  def send_files(chat_id, files, opts) do
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.get(opts, :source_chat)
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    if FileType.all_images?(files) and length(files) > 1 do
      send_media_group(
        chat_id,
        Enum.map(files, fn %DownloadedFile{} = file ->
          {file.file_name, {:file_content, file.file_content, file.file_name}, source_url,
           file.download_url, thumbnail_url}
        end),
        [
          source_chat: source_chat,
          caption: caption,
          message_thread_id: message_thread_id
        ] ++ url_metadata_opts
      )
    else
      Enum.each(files, fn %DownloadedFile{} = file ->
        send_downloaded_file(
          chat_id,
          file,
          [
            source_url: source_url,
            source_chat: source_chat,
            caption: caption,
            thumbnail_url: thumbnail_url,
            message_thread_id: message_thread_id
          ] ++ url_metadata_opts
        )
      end)
    end
  end

  def send_downloaded_file(chat_id, %DownloadedFile{} = file, opts) do
    store_download_url? = Keyword.get(opts, :store_download_url?, true)
    download_url = download_url_for_file(file, opts, store_download_url?)

    opts =
      opts
      |> Keyword.delete(:store_download_url?)
      |> Keyword.delete(:download_url)
      |> put_optional_keyword(:download_url, download_url)

    send_file(
      chat_id,
      file.file_name,
      {:file_content, file.file_content, file.file_name},
      opts
    )
  end

  def send_filenames(chat_id, filenames, opts) do
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.get(opts, :source_chat)
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    if FileType.all_images?(filenames) and length(filenames) > 1 do
      send_media_group(
        chat_id,
        Enum.map(filenames, fn filename ->
          {filename, {:file, filename}, source_url, nil, thumbnail_url}
        end),
        [
          source_chat: source_chat,
          caption: caption,
          message_thread_id: message_thread_id
        ] ++ url_metadata_opts
      )
    else
      Enum.each(filenames, fn filename ->
        send_file(
          chat_id,
          filename,
          {:file, filename},
          [
            source_url: source_url,
            source_chat: source_chat,
            caption: caption,
            thumbnail_url: thumbnail_url,
            message_thread_id: message_thread_id
          ] ++ url_metadata_opts
        )
      end)
    end
  end

  def send_file(chat_id, file_name, file_content, opts) do
    content =
      case file_content do
        {:file, file} -> {:file, file}
        {:file_content, file_content, file_name} -> {:file_content, file_content, file_name}
      end

    caption = Keyword.get(opts, :caption, "")
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    source_chat = Keyword.get(opts, :source_chat) || %{id: chat_id}
    message_thread_id = Keyword.get(opts, :message_thread_id)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    opts =
      [
        caption: caption,
        source_url: source_url,
        download_url: download_url,
        thumbnail_url: thumbnail_url,
        source_chat: source_chat,
        message_thread_id: message_thread_id
      ] ++ url_metadata_opts

    upload_too_large? = upload_too_large?(content)

    Logger.debug(
      "Telegram media send started " <>
        "media_type=#{FileType.media_type(file_name)} " <>
        "file_name=#{LogFormat.value(file_name)} " <>
        "source_url=#{LogFormat.url(source_url)} " <>
        "download_url=#{LogFormat.url(download_url)} " <>
        "upload_too_large=#{upload_too_large?}"
    )

    if upload_too_large? do
      handle_upload_too_large(chat_id, file_name, content, opts)
    else
      do_send_file(
        chat_id,
        file_name,
        content,
        opts
      )
    end
  end

  defp download_url_for_file(_file, _opts, false), do: nil

  defp download_url_for_file(%DownloadedFile{} = file, opts, true) do
    Keyword.get(opts, :download_url) || file.download_url
  end

  defp send_media_group(chat_id, files, opts) do
    source_chat = Keyword.get(opts, :source_chat) || %{id: chat_id}
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    case TelegramClient.send_media_group(chat_id, files,
           caption: caption,
           message_thread_id: message_thread_id
         ) do
      {:ok, messages} ->
        files
        |> Enum.zip(messages)
        |> Enum.each(fn {file, msg} ->
          index_media_group_file(file, msg, chat_id, source_chat, caption, url_metadata_opts)
        end)

      {:error, _reason} ->
        Logger.error("Failed to send media group")

        Enum.each(files, fn file ->
          resend_media_group_file(
            file,
            chat_id,
            [
              source_chat: source_chat,
              caption: caption,
              message_thread_id: message_thread_id
            ] ++ url_metadata_opts
          )
        end)
    end
  end

  defp index_media_group_file(file, msg, chat_id, source_chat, caption, url_metadata_opts) do
    {content, source_fields} = media_group_file_fields(file)

    case encode_index_image(content) do
      {:ok, image} ->
        %{
          image: image,
          caption: caption,
          file_id: MessageInfo.file_id(msg),
          belongs_to_id: chat_id
        }
        |> Map.merge(source_fields)
        |> PhotoIndex.put_url_metadata_fields(url_metadata_opts)
        |> Map.merge(MessageInfo.source_message_fields(source_chat, msg))
        |> PhotoIndex.create_photo()

      {:error, _reason} ->
        Logger.warning("Skipping Typesense indexing: unsupported image")
        :error
    end
  end

  defp resend_media_group_file(file, chat_id, opts) do
    {file_name, content, source_url, download_url, thumbnail_url} =
      media_group_file_send_fields(file)

    send_file(
      chat_id,
      file_name,
      content,
      opts
      |> put_optional_keyword(:source_url, source_url)
      |> put_optional_keyword(:download_url, download_url)
      |> put_optional_keyword(:thumbnail_url, thumbnail_url)
    )
  end

  defp media_group_file_fields({_file_name, content, source_url, download_url, thumbnail_url}) do
    {content,
     %{url: source_url}
     |> put_optional(:download_url, download_url)
     |> put_optional(:thumbnail_url, thumbnail_url)}
  end

  defp media_group_file_fields({_file_name, content, source_url, download_url}) do
    {content, put_optional(%{url: source_url}, :download_url, download_url)}
  end

  defp media_group_file_fields({_file_name, content, source_url}),
    do: {content, %{url: source_url}}

  defp media_group_file_fields({_file_name, content}), do: {content, %{}}

  defp media_group_file_send_fields(
         {file_name, content, source_url, download_url, thumbnail_url}
       ),
       do: {file_name, content, source_url, download_url, thumbnail_url}

  defp media_group_file_send_fields({file_name, content, source_url, download_url}),
    do: {file_name, content, source_url, download_url, nil}

  defp media_group_file_send_fields({file_name, content, source_url}),
    do: {file_name, content, source_url, nil, nil}

  defp media_group_file_send_fields({file_name, content}),
    do: {file_name, content, nil, nil, nil}

  defp handle_upload_too_large(chat_id, file_name, content, opts) do
    case FileType.extension(file_name) do
      ext when ext in [".mp4", ".webm", ".mov", ".m4v", ".mkv"] ->
        send_oversized_video_preview(chat_id, content, opts)

      ".gif" ->
        send_gif_animation(
          chat_id,
          content,
          Keyword.fetch!(opts, :caption),
          Keyword.get(opts, :message_thread_id),
          opts
        )

      _extension ->
        Telegram.send_message(chat_id, @telegram_file_too_large_message)
        {:error, :telegram_file_too_large}
    end
  end

  defp send_oversized_video_preview(chat_id, content, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    source_chat = Keyword.fetch!(opts, :source_chat)
    message_thread_id = Keyword.get(opts, :message_thread_id)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    {prepared_content, video_metadata} = VideoUpload.prepare(content)

    with {:ok, %DownloadedFile{} = preview_file, indexed_thumbnail_url} <-
           oversized_video_preview(prepared_content, video_metadata, source_url, thumbnail_url),
         {:ok, msg} <-
           ExGram.send_photo(
             chat_id,
             {:file_content, preview_file.file_content, preview_file.file_name},
             telegram_send_opts(oversized_video_caption(caption), message_thread_id)
           ),
         file_id when is_binary(file_id) <- MessageInfo.file_id(msg) do
      %{
        image: Base.encode64(preview_file.file_content),
        caption: caption,
        file_id: file_id,
        media_type: "photo",
        url: source_url,
        belongs_to_id: chat_id
      }
      |> put_optional(:download_url, download_url)
      |> put_optional(:thumbnail_url, indexed_thumbnail_url)
      |> PhotoIndex.put_url_metadata_fields(url_metadata_opts)
      |> Map.merge(MessageInfo.source_message_fields(source_chat, msg))
      |> PhotoIndex.index_photo()

      store_sent_video_preview(preview_file, source_url)
      :ok
    else
      _reason ->
        Telegram.send_message(chat_id, @telegram_file_too_large_message)
        {:error, :telegram_file_too_large}
    end
  end

  defp oversized_video_preview(prepared_content, video_metadata, source_url, thumbnail_url) do
    case VideoUpload.cover(prepared_content, video_metadata) do
      {:ok, video_cover} ->
        {:ok,
         %DownloadedFile{
           file_name: video_cover.file_name,
           file_content: video_cover.file_content
         }, nil}

      :error ->
        case ThumbnailDownload.preview_image(thumbnail_url, source_url) do
          {:ok, %DownloadedFile{} = file} -> {:ok, file, thumbnail_url}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp oversized_video_caption(""), do: @telegram_video_too_large_thumbnail_message
  defp oversized_video_caption(nil), do: @telegram_video_too_large_thumbnail_message

  defp oversized_video_caption(caption) when is_binary(caption) do
    caption <> "\n\n" <> @telegram_video_too_large_thumbnail_message
  end

  defp do_send_file(chat_id, file_name, content, opts) do
    caption = Keyword.fetch!(opts, :caption)
    message_thread_id = Keyword.get(opts, :message_thread_id)

    case FileType.extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg", ".webp"] ->
        send_photo(chat_id, content, caption, message_thread_id, opts)

      ext when ext in [".mp4", ".webm", ".mov", ".m4v", ".mkv"] ->
        send_video(chat_id, content, caption, message_thread_id, opts)

      ".gif" ->
        send_gif_animation(chat_id, content, caption, message_thread_id, opts)

      _extension ->
        ExGram.send_document(chat_id, content, telegram_send_opts(caption, message_thread_id))
    end
  end

  defp send_photo(chat_id, content, caption, message_thread_id, opts) do
    {:ok, msg} =
      ExGram.send_photo(chat_id, content, telegram_send_opts(caption, message_thread_id))

    case encode_index_image(content) do
      {:ok, image} ->
        %{
          image: image,
          caption: caption,
          file_id: MessageInfo.file_id(msg),
          url: Keyword.get(opts, :source_url),
          belongs_to_id: chat_id
        }
        |> put_optional(:download_url, Keyword.get(opts, :download_url))
        |> put_optional(:thumbnail_url, Keyword.get(opts, :thumbnail_url))
        |> PhotoIndex.put_url_metadata_fields(PhotoIndex.url_metadata_opts(opts))
        |> Map.merge(MessageInfo.source_message_fields(Keyword.fetch!(opts, :source_chat), msg))
        |> PhotoIndex.index_photo()

      {:error, _reason} ->
        Logger.warning("Skipping Typesense indexing: unsupported image")
        :error
    end
  end

  defp send_video(chat_id, content, caption, message_thread_id, opts) do
    {prepared_content, video_metadata} = VideoUpload.prepare(content)
    video_cover = VideoUpload.cover(prepared_content, video_metadata)

    case ExGram.send_video(
           chat_id,
           prepared_content,
           video_send_opts(caption, video_metadata, video_cover, message_thread_id)
         ) do
      {:ok, msg} = response ->
        index_sent_video_preview(
          chat_id,
          msg,
          Keyword.put(opts, :video_cover, video_cover)
        )

        response

      {:error, _reason} = error ->
        error
    end
  end

  defp send_gif_animation(chat_id, content, caption, message_thread_id, opts) do
    {prepared_content, metadata} = AnimationUpload.prepare(content)

    if upload_too_large?(prepared_content) do
      Telegram.send_message(chat_id, @telegram_file_too_large_message)
      {:error, :telegram_file_too_large}
    else
      case ExGram.send_animation(
             chat_id,
             prepared_content,
             animation_send_opts(caption, metadata, message_thread_id)
           ) do
        {:ok, msg} = response ->
          index_sent_animation(
            chat_id,
            msg,
            opts
            |> Keyword.put(:prepared_content, prepared_content)
            |> Keyword.put(:video_metadata, metadata)
          )

          response

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp animation_send_opts(caption, metadata, message_thread_id) do
    [caption: caption]
    |> maybe_put_video_metadata(:width, metadata)
    |> maybe_put_video_metadata(:height, metadata)
    |> maybe_put_video_metadata(:duration, metadata)
    |> put_optional_keyword(:message_thread_id, message_thread_id)
  end

  defp telegram_send_opts(caption, message_thread_id) do
    [caption: caption]
    |> put_optional_keyword(:message_thread_id, message_thread_id)
  end

  defp video_send_opts(caption, video_metadata, video_cover, message_thread_id) do
    [supports_streaming: true, caption: caption]
    |> maybe_put_video_metadata(:width, video_metadata)
    |> maybe_put_video_metadata(:height, video_metadata)
    |> maybe_put_video_metadata(:duration, video_metadata)
    |> maybe_put_video_preview_files(video_cover)
    |> put_optional_keyword(:message_thread_id, message_thread_id)
  end

  defp maybe_put_video_metadata(opts, key, metadata) when is_map(metadata) do
    case Map.get(metadata, key) do
      value when is_integer(value) and value > 0 -> Keyword.put(opts, key, value)
      _ -> opts
    end
  end

  defp maybe_put_video_preview_files(
         opts,
         {:ok, %{file_content: file_content, file_name: file_name}} = video_cover
       )
       when is_binary(file_content) and is_binary(file_name) do
    opts
    |> Keyword.put(:cover, {:file_content, file_content, file_name})
    |> maybe_put_video_thumbnail_file(video_cover)
  end

  defp maybe_put_video_preview_files(opts, _video_cover), do: opts

  defp maybe_put_video_thumbnail_file(
         opts,
         {:ok,
          %{
            thumbnail_file_content: file_content,
            thumbnail_file_name: file_name
          }}
       )
       when is_binary(file_content) and is_binary(file_name) do
    Keyword.put(opts, :thumbnail, {:file_content, file_content, file_name})
  end

  defp maybe_put_video_thumbnail_file(opts, _video_cover), do: opts

  defp index_sent_video_preview(chat_id, msg, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    source_chat = Keyword.fetch!(opts, :source_chat)
    video_cover = Keyword.get(opts, :video_cover)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    indexed_thumbnail_url =
      if match?({:ok, _cover}, video_cover), do: nil, else: thumbnail_url

    case MessageInfo.sent_media_file_id(msg) do
      file_id when is_binary(file_id) ->
        case video_index_image(msg, source_url, thumbnail_url, video_cover) do
          {:ok, %DownloadedFile{} = file} ->
            %{
              image: Base.encode64(file.file_content),
              caption: caption,
              file_id: file_id,
              media_type: "video",
              url: source_url,
              belongs_to_id: chat_id
            }
            |> put_optional(:download_url, download_url)
            |> put_optional(:thumbnail_url, indexed_thumbnail_url)
            |> PhotoIndex.put_url_metadata_fields(url_metadata_opts)
            |> Map.merge(MessageInfo.source_message_fields(source_chat, msg))
            |> PhotoIndex.index_photo()

            store_sent_video_preview(file, source_url)

          :error ->
            Logger.warning("Skipping video preview indexing")
            :error
        end

      _ ->
        Logger.warning("Skipping video preview indexing: missing sent video file_id")
        :error
    end
  end

  defp video_index_image(msg, source_url, thumbnail_url, video_cover) do
    first_preview([
      fn -> ThumbnailDownload.from_message(msg) end,
      fn -> video_cover_file(video_cover) end,
      fn -> ThumbnailDownload.preview_image(thumbnail_url, source_url) end
    ])
  end

  defp index_sent_animation(chat_id, msg, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    source_chat = Keyword.fetch!(opts, :source_chat)
    url_metadata_opts = PhotoIndex.url_metadata_opts(opts)

    case MessageInfo.sent_media_file_id(msg) do
      file_id when is_binary(file_id) ->
        case animation_index_image(msg, opts, thumbnail_url, source_url) do
          {:ok, %DownloadedFile{} = file} ->
            %{
              image: Base.encode64(file.file_content),
              caption: caption,
              file_id: file_id,
              media_type: "gif",
              url: source_url,
              belongs_to_id: chat_id
            }
            |> put_optional(:download_url, download_url)
            |> put_optional(:thumbnail_url, thumbnail_url)
            |> PhotoIndex.put_url_metadata_fields(url_metadata_opts)
            |> Map.merge(MessageInfo.source_message_fields(source_chat, msg))
            |> PhotoIndex.index_photo()

          :error ->
            Logger.warning("Skipping gif indexing")
            :error
        end

      _ ->
        Logger.warning("Skipping gif indexing: missing sent animation file_id")
        :error
    end
  end

  defp animation_index_image(msg, opts, thumbnail_url, source_url) do
    prepared_content = Keyword.get(opts, :prepared_content)
    video_metadata = Keyword.get(opts, :video_metadata, %{})

    first_preview([
      fn -> ThumbnailDownload.from_message(msg) end,
      fn -> video_cover_file(maybe_video_cover(prepared_content, video_metadata)) end,
      fn -> ThumbnailDownload.preview_image(thumbnail_url, source_url) end
    ])
  end

  defp first_preview(funs) do
    Enum.find_value(funs, :error, fn fun ->
      case fun.() do
        {:ok, %DownloadedFile{} = file} -> {:ok, file}
        _ -> nil
      end
    end)
  end

  defp maybe_video_cover(prepared_content, video_metadata)
       when not is_nil(prepared_content) and is_map(video_metadata) do
    VideoUpload.cover(prepared_content, video_metadata)
  end

  defp maybe_video_cover(_prepared_content, _video_metadata), do: :error

  defp video_cover_file({:ok, %{file_content: file_content, file_name: file_name}})
       when is_binary(file_content) and is_binary(file_name) do
    {:ok, %DownloadedFile{file_name: file_name, file_content: file_content}}
  end

  defp video_cover_file(_video_cover), do: :error

  defp store_sent_video_preview(%DownloadedFile{} = file, source_url) do
    cache_url = file.download_url || source_url

    if is_binary(cache_url) do
      FileHelper.write_file(file.file_name, file.file_content, cache_url)
    end
  end

  defp upload_too_large?({:file_content, file_content, _file_name}) do
    byte_size(file_content) > @telegram_upload_max_file_size
  end

  defp upload_too_large?({:file, file_path}) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size > @telegram_upload_max_file_size
      {:error, _reason} -> false
    end
  end

  defp encode_index_image({:file, file}) do
    encode_index_image({:file_content, File.read!(file), Path.basename(file)})
  end

  defp encode_index_image({:file_content, file_content, file_name}) do
    case IndexImage.jpeg_bytes(file_name, file_content) do
      {:ok, jpeg} -> {:ok, Base.encode64(jpeg)}
      {:error, reason} -> {:error, reason}
    end
  end
end
