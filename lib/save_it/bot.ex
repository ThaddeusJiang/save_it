defmodule SaveIt.Bot do
  @moduledoc false

  require Logger

  import SaveIt.SmallHelper.UrlHelper, only: [direct_media_url?: 1]

  alias SaveIt.DownloadContext
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive
  alias SaveIt.GoogleOAuth2DeviceFlow
  alias SaveIt.UrlMetadata
  alias SaveIt.VideoUpload

  alias SaveIt.PhotoService

  alias SmallSdk.BadNews
  alias SmallSdk.Cobalt
  alias SmallSdk.HlsDownloader
  alias SmallSdk.LinkPreview
  alias SmallSdk.Telegram
  alias SmallSdk.WebDownloader

  @bot :save_it_bot

  @progress [
    "Searching 🔎",
    "Downloading 💦",
    "Uploading 💭",
    "Have fun! 🎉"
  ]

  @similar_photos_found_message "Similar photos found."
  @telegram_upload_max_file_size 50 * 1024 * 1024
  @telegram_file_too_large_message "💔 File is too large for Telegram Bot API upload."
  @telegram_video_too_large_thumbnail_message "Video downloaded; Telegram upload was too large."

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")

  command("search", description: "Search photos")
  command("delete", description: "Delete message")
  command("detail", description: "Show media details")

  command("google_drive_login", description: "Connect Google Drive")
  command("google_drive_folder", description: "Set Google Drive folder ID")

  command("about", description: "Know more about this bot")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot, do: @bot

  def handle({:command, :start, _msg}, context) do
    answer(context, "Hi! I'm a bot that can download images and videos, just give me a link.")
  end

  def handle({:command, :about, %{chat: chat}}, _context) do
    bot_info = about_bot_info()

    send_message(chat.id, """
    SaveIt can download images and videos, just give me a link.

    Chat: #{about_chat_type(chat)}
    Public: #{about_public_status(chat)}
    Bot admin: #{about_bot_admin_status(chat, bot_info)}
    Privacy Mode: #{about_privacy_mode_status(bot_info)}

    Created by @ThaddeusJiang, powered by Cobalt, Typesense, and Elixir.Access

    Give a star ⭐ if you like it, https://github.com/ThaddeusJiang/save_it
    """)
  end

  def handle({:command, :google_drive_login, %{chat: chat} = message}, _context) do
    case google_drive_login_permission(chat, Map.get(message, :from)) do
      :ok ->
        login_google(chat)

      {:error, :not_admin} ->
        send_message(chat.id, "You are not an administrator, you can't connect Google Drive.")

      {:error, :unsupported_chat} ->
        send_message(chat.id, "You can't connect Google Drive in this chat.")
    end
  end

  def handle({:command, :google_drive_folder, %{chat: chat, text: text}}, _context) do
    folder_id = normalize_command_text(text)

    if folder_id == "" do
      send_message(chat.id, "Please provide a Google Drive folder ID.")
    else
      FileHelper.set_google_drive_folder_id(chat.id, folder_id)
      send_message(chat.id, "Google Drive folder ID set successfully.")
    end
  end

  def handle({:command, :search, %{chat: chat, photo: [_ | _] = photos} = message}, _context) do
    handle_uploaded_photo(message, chat, "/search", photos)
  end

  def handle({:command, :search, %{chat: chat, text: nil}}, _context) do
    send_message(
      chat.id,
      "What do you want to search? animal, food, etc. Or upload a photo with /search."
    )
  end

  def handle({:command, :search, %{chat: chat, text: text}}, _context)
      when is_binary(text) do
    q = String.trim(text)

    case q do
      "" ->
        send_message(chat.id, "What do you want to search? animal, food, etc.")

      _ ->
        photos = safe_typesense_search_photos(q, belongs_to_id: chat.id)
        answer_photos(chat.id, photos)
    end
  end

  def handle({:command, :detail, %{chat: chat, reply_to_message: nil}}, _context) do
    send_message(chat.id, "reply a photo or video with /detail command.")
  end

  def handle({:command, :detail, %{chat: chat, reply_to_message: reply_to_message}}, _context) do
    case detail_media_file_id(reply_to_message) do
      file_id when is_binary(file_id) ->
        handle_detail_command(chat.id, reply_to_message, file_id)

      _ ->
        send_message(chat.id, "reply a photo or video with /detail command.")
    end
  end

  def handle({:command, :delete, %{chat: chat, reply_to_message: nil}}, _ctx) do
    send_message(chat.id, "reply a message with /delete command.")
  end

  def handle(
        {:command, :delete,
         %{chat: chat, message_id: message_id, from: from, reply_to_message: reply_to_message}},
        _ctx
      ) do
    {:ok, %{id: bot_id, username: bot_username}} = ExGram.get_me()

    if Enum.member?([bot_id, from.id], reply_to_message.from.id) do
      handle_delete_command(chat.id, message_id, reply_to_message)
    else
      send_message(chat.id, "Only delete messages from @#{bot_username} and yourself.")
    end
  end

  # caption: nil -> find same photos
  # caption: contains /search -> search similar photos; otherwise, find same photos
  def handle({:message, %{chat: chat, photo: [_ | _] = photos} = message}, _ctx) do
    handle_uploaded_photo(message, chat, Map.get(message, :caption), photos)
  end

  def handle({:message, %{chat: chat, video: %{file_id: _file_id} = video} = message}, _ctx) do
    handle_uploaded_video(message, chat, Map.get(message, :caption), video)
  end

  def handle({:text, text, %{chat: chat, photo: [_ | _] = photos} = message}, _context)
      when is_binary(text) do
    case extract_urls_from_string(text) do
      [] -> handle_uploaded_photo(message, chat, text, photos)
      urls -> handle_text_urls(text, message, urls)
    end
  end

  def handle({:text, text, message}, _context) do
    case extract_urls_from_string(text) do
      [] -> :ok
      urls -> handle_text_urls(text, message, urls)
    end
  end

  def handle({:edited_message, %{photo: nil}}, _context) do
    Logger.debug("Ignoring edited message without photo")
    # Edited search commands are ignored for now.
    {:ok, nil}
  end

  def handle({:edited_message, %{chat: chat, caption: caption, photo: photos}}, _context) do
    file_id = photos |> List.last() |> Map.get(:file_id)
    PhotoService.update_photo_caption!(file_id, chat.id, caption)
  end

  def handle({:update, _update}, _context) do
    Logger.debug("Ignoring unsupported update")
    {:ok, nil}
  end

  def handle({:message, _message}, _context) do
    Logger.debug("Ignoring unsupported message")
    {:ok, nil}
  end

  defp answer_photos(chat_id, []) do
    send_message(chat_id, "No photos found.")
  end

  defp answer_photos(chat_id, [photo]) do
    send_similar_media(chat_id, photo)
    :ok
  end

  defp answer_photos(chat_id, similar_photos) do
    media = Enum.map(similar_photos, &saved_media_group_input/1)

    case ExGram.send_media_group(chat_id, media) do
      {:ok, _response} ->
        :ok

      {:error, _reason} ->
        Logger.warning(
          "Failed to send similar media group, falling back to individual media",
          kind: :telegram_media_group_failed
        )

        Enum.each(similar_photos, &send_similar_media(chat_id, &1))
        :ok
    end
  end

  defp handle_text_urls(text, %{chat: chat, message_id: message_id} = message, urls) do
    message = Map.put_new(message, :text, text)

    has_success? =
      urls
      |> Enum.map(&process_url(chat, &1, message))
      |> Enum.any?(&(&1 == :ok))

    if has_success? do
      delete_message(chat.id, message_id)
    end
  end

  defp send_similar_media(chat_id, media) do
    case send_saved_media(chat_id, media) do
      {:ok, _response} ->
        :ok

      {:error, _reason} ->
        Logger.warning(
          "Skipping unavailable similar media",
          file_id: media["file_id"]
        )

        :error
    end
  end

  defp answer_similar_photos(chat_id, []) do
    answer_photos(chat_id, [])
  end

  defp answer_similar_photos(chat_id, photos) when is_list(photos) do
    send_message(chat_id, @similar_photos_found_message)
    answer_photos(chat_id, photos)
  end

  defp answer_similar_photos_if_any(_chat_id, []), do: nil

  defp answer_similar_photos_if_any(chat_id, photos) when is_list(photos),
    do: answer_similar_photos(chat_id, photos)

  defp handle_uploaded_photo(message, chat, caption, photos) do
    photo = List.last(photos)
    file = ExGram.get_file!(photo.file_id)
    file_content = Telegram.download_file_content!(file.file_path)
    file_name = telegram_file_name(file, photo.file_id, ".jpg")

    FileHelper.write_file(file_name, file_content, telegram_cache_key("photo", file.file_id))
    GoogleDrive.upload_file_content(chat.id, file_content, file_name)

    %{
      image: Base.encode64(file_content),
      caption: searchable_caption(caption),
      file_id: file.file_id,
      media_type: "photo",
      belongs_to_id: chat.id
    }
    |> Map.merge(source_message_fields(chat, message))
    |> safe_typesense_create_photo()
    |> answer_similar_for_uploaded_media(chat.id, caption)
  end

  defp handle_uploaded_video(message, chat, caption, video) do
    typesense_photo =
      video
      |> video_thumbnail()
      |> create_video_thumbnail_index(chat, message, caption, video.file_id)

    store_uploaded_video_file(chat.id, video)
    answer_similar_for_uploaded_media(typesense_photo, chat.id, caption)
  end

  defp create_video_thumbnail_index(nil, _chat, _message, _caption, _file_id), do: nil

  defp create_video_thumbnail_index(thumbnail, chat, message, caption, file_id) do
    thumbnail_file = ExGram.get_file!(thumbnail.file_id)
    thumbnail_content = Telegram.download_file_content!(thumbnail_file.file_path)

    %{
      image: Base.encode64(thumbnail_content),
      caption: searchable_caption(caption),
      file_id: file_id,
      media_type: "video",
      belongs_to_id: chat.id
    }
    |> Map.merge(source_message_fields(chat, message))
    |> safe_typesense_create_photo()
  end

  defp store_uploaded_video_file(chat_id, video) do
    case ExGram.get_file(video.file_id) do
      {:ok, file} ->
        store_uploaded_video_file_content(chat_id, video, file)

      {:error, reason} ->
        handle_uploaded_video_file_error(reason)
    end
  end

  defp store_uploaded_video_file_content(chat_id, video, file) do
    case Telegram.download_file_content(file.file_path) do
      {:ok, file_content} ->
        file_name = Map.get(video, :file_name) || telegram_file_name(file, video.file_id, ".mp4")
        FileHelper.write_file(file_name, file_content, telegram_cache_key("video", video.file_id))
        upload_to_google_drive_if_configured(chat_id, file_content, file_name)
        :ok

      {:error, reason} ->
        handle_uploaded_video_file_error(reason)
    end
  end

  defp handle_uploaded_video_file_error(_reason) do
    Logger.warning("Skipping local backup for Telegram video")
    :error
  end

  defp upload_to_google_drive_if_configured(chat_id, file_content, file_name) do
    if GoogleDrive.configured?(chat_id) do
      GoogleDrive.upload_file_content(chat_id, file_content, file_name)
    else
      :ok
    end
  end

  defp video_thumbnail(video) do
    Map.get(video, :thumbnail) || Map.get(video, :thumb)
  end

  defp telegram_cache_key(media_type, file_id) do
    "telegram:#{media_type}:#{file_id}"
  end

  defp answer_similar_for_uploaded_media(nil, _chat_id, _caption), do: :ok

  defp answer_similar_for_uploaded_media(typesense_photo, chat_id, caption) do
    similar_photos =
      typesense_photo["id"]
      |> safe_typesense_search_similar_photos(
        distance_threshold: similar_search_distance_threshold(caption),
        belongs_to_id: chat_id
      )
      |> exclude_uploaded_media(typesense_photo)

    if search_command_caption?(caption) do
      answer_similar_photos(chat_id, similar_photos)
    else
      answer_similar_photos_if_any(chat_id, similar_photos)
    end
  end

  defp similar_search_distance_threshold(caption) do
    if search_command_caption?(caption), do: 0.4, else: 0.1
  end

  defp exclude_uploaded_media(photos, uploaded_media) when is_list(photos) do
    uploaded_file_id = Map.get(uploaded_media, "file_id")
    uploaded_id = Map.get(uploaded_media, "id")

    Enum.reject(photos, fn photo ->
      same_present_value?(Map.get(photo, "file_id"), uploaded_file_id) or
        same_present_value?(Map.get(photo, "id"), uploaded_id)
    end)
  end

  defp same_present_value?(left, right) when is_binary(left) and is_binary(right) do
    left != "" and left == right
  end

  defp same_present_value?(_left, _right), do: false

  defp searchable_caption(caption) do
    if search_command_caption?(caption), do: "", else: strip_urls_from_text(caption)
  end

  defp search_command_caption?(caption) when is_binary(caption) do
    String.contains?(caption, "/search")
  end

  defp search_command_caption?(_caption), do: false

  defp telegram_file_name(file, file_id, fallback_extension) do
    case Map.get(file, :file_path) do
      file_path when is_binary(file_path) and file_path != "" ->
        Path.basename(file_path)

      _ ->
        file_id <> fallback_extension
    end
  end

  defp send_saved_media(chat_id, %{"media_type" => "video"} = media) do
    ExGram.send_video(chat_id, media["file_id"],
      caption: media["caption"],
      supports_streaming: true
    )
  end

  defp send_saved_media(chat_id, media) do
    ExGram.send_photo(chat_id, media["file_id"], caption: media["caption"])
  end

  defp saved_media_group_input(%{"media_type" => "video"} = media) do
    %ExGram.Model.InputMediaVideo{
      type: "video",
      media: media["file_id"],
      caption: media["caption"],
      supports_streaming: true
    }
  end

  defp saved_media_group_input(media) do
    %ExGram.Model.InputMediaPhoto{
      type: "photo",
      media: media["file_id"],
      caption: media["caption"]
    }
  end

  defp extract_urls_from_string(str) do
    regex = ~r/http[s]?:\/\/[^\s]+/
    matches = Regex.scan(regex, str)

    # 扁平化匹配结果，因为Regex.scan返回的是一个列表的列表
    Enum.map(matches, fn [url] -> url end)
  end

  defp get_download_url(url) do
    cond do
      direct_media_url?(url) ->
        {:ok, url}

      BadNews.bad_news_url?(url) ->
        BadNews.get_download_url(url)

      true ->
        Cobalt.get_download_url(url)
    end
  end

  defp process_url(chat, url, message) do
    chat_id = chat.id

    Logger.debug("URL processing started chat_id=#{chat_id} source_url=#{format_log_url(url)}")

    {:ok, progress_message} = send_message(chat_id, Enum.at(@progress, 0))

    context = %DownloadContext{
      chat_id: chat_id,
      chat: chat,
      progress_message_id: progress_message.message_id,
      original_url: url,
      message: message
    }

    case resolve_download_url(url) do
      {:ok, m3u8_url, :hls} ->
        Logger.debug(
          "URL download resolved result=hls " <>
            "source_url=#{format_log_url(url)} download_url=#{format_log_url(m3u8_url)}"
        )

        handle_hls_download(%{context | cache_url: url, download_url: m3u8_url}, m3u8_url)

      {:ok, purge_url, download_urls} ->
        Logger.debug(
          "URL download resolved result=multi " <>
            "source_url=#{format_log_url(url)} file_count=#{length(download_urls)}"
        )

        handle_multi_file_download(%{context | purge_url: purge_url}, download_urls)

      {:ok, download_url} ->
        Logger.debug(
          "URL download resolved result=single " <>
            "source_url=#{format_log_url(url)} download_url=#{format_log_url(download_url)}"
        )

        handle_single_file_download(%{
          context
          | download_url: download_url,
            cache_url: download_url
        })

      {:error, reason} ->
        Logger.debug("URL download resolve failed source_url=#{format_log_url(url)}")
        handle_download_failure(context, "💔 Failed to get download URL.", reason)
    end
  end

  defp resolve_download_url(url) do
    case Application.get_env(:save_it, :download_url_resolver) do
      nil -> get_download_url(url)
      resolver -> resolver.get_download_url(url)
    end
  end

  defp handle_hls_download(%DownloadContext{} = context, m3u8_url) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case hls_downloader().download(m3u8_url) do
      {:ok, %DownloadedFile{} = file} ->
        Logger.debug(
          "URL HLS downloaded file_name=#{format_log_value(file.file_name)} " <>
            "download_url=#{format_log_url(context.download_url)}"
        )

        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_downloaded_file(context.chat_id, file, download_send_opts(context))

        finalize_single_download(context, file)

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading HLS video.", reason)
    end
  end

  defp hls_downloader do
    Application.get_env(:save_it, :hls_downloader, HlsDownloader)
  end

  defp handle_multi_file_download(%DownloadContext{} = context, download_urls) do
    case FileHelper.get_downloaded_files(context.purge_url) do
      nil ->
        download_and_store_files(context, download_urls)

      downloaded_files ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_filenames(context.chat_id, downloaded_files, download_send_opts(context))

        delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_files(%DownloadContext{} = context, download_urls) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_files(download_urls) do
      {:ok, files} ->
        Logger.debug("URL files downloaded file_count=#{length(files)}")

        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_files(context.chat_id, files, download_send_opts(context))

        delete_message(context.chat_id, context.progress_message_id)
        FileHelper.write_folder(context.purge_url, files)
        GoogleDrive.upload_files(context.chat_id, files)

        Logger.info("resource_created source=url_download file_count=#{length(files)}",
          ansi_color: :green
        )

        :ok

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading file.", reason)
    end
  end

  defp handle_single_file_download(%DownloadContext{} = context) do
    case FileHelper.get_downloaded_file(context.download_url) do
      nil ->
        download_and_store_file(context)

      downloaded_file ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_file(
          context.chat_id,
          downloaded_file,
          {:file, downloaded_file},
          download_send_opts(context)
        )

        delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_file(%DownloadContext{} = context) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_file(context.download_url) do
      {:ok, %DownloadedFile{} = file} ->
        Logger.debug(
          "URL file downloaded file_name=#{format_log_value(file.file_name)} " <>
            "download_url=#{format_log_url(context.download_url)}"
        )

        if url_download_media_file?(file.file_name) do
          update_message(
            context.chat_id,
            context.progress_message_id,
            Enum.slice(@progress, 0..2)
          )

          bot_send_downloaded_file(context.chat_id, file, download_send_opts(context))

          finalize_single_download(context, file)
        else
          handle_non_media_download(context)
        end

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading file.", reason)
    end
  end

  defp handle_non_media_download(%DownloadContext{} = context) do
    case download_fallback_thumbnail(context) do
      {:ok, %DownloadedFile{} = file, source} ->
        case source do
          :telegram_thumbnail ->
            Logger.warning("Saved Telegram thumbnail fallback after non-media URL download")

          :webpage_preview ->
            Logger.warning("Saved webpage preview fallback after non-media URL download")
        end

        save_thumbnail_fallback(context, file, source)

      {:error, _fallback_reasons} ->
        Logger.warning("No thumbnail fallback available after non-media URL download")

        update_message(context.chat_id, context.progress_message_id, "💔 No image preview found.")
        :error
    end
  end

  defp handle_download_failure(%DownloadContext{} = context, failure_message, _failure_reason) do
    case download_fallback_thumbnail(context) do
      {:ok, %DownloadedFile{} = file, source} ->
        log_thumbnail_fallback_success(source)
        save_thumbnail_fallback(context, file, source)

      {:error, _fallback_reasons} ->
        Logger.warning("No thumbnail fallback available after link download failed")

        update_message(context.chat_id, context.progress_message_id, failure_message)
        :error
    end
  end

  defp download_fallback_thumbnail(%DownloadContext{} = context) do
    case download_message_thumbnail(context.message) do
      {:ok, %DownloadedFile{} = file} ->
        {:ok, file, :telegram_thumbnail}

      {:error, telegram_reason} ->
        case download_webpage_preview(context) do
          {:ok, %DownloadedFile{} = file} ->
            {:ok, file, :webpage_preview}

          {:error, preview_reason} ->
            {:error, %{telegram_thumbnail: telegram_reason, webpage_preview: preview_reason}}
        end
    end
  end

  defp log_thumbnail_fallback_success(:telegram_thumbnail) do
    Logger.warning("Saved Telegram thumbnail fallback after link download failed")
  end

  defp log_thumbnail_fallback_success(:webpage_preview) do
    Logger.warning("Saved webpage preview fallback after link download failed")
  end

  defp save_thumbnail_fallback(%DownloadContext{} = context, %DownloadedFile{} = file, source) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

    bot_send_downloaded_file(
      context.chat_id,
      file,
      download_send_opts(context, store_thumbnail_url?: source == :webpage_preview)
      |> Keyword.put(:store_download_url?, false)
    )

    finalize_thumbnail_download(context, file)
  end

  defp download_send_opts(%DownloadContext{} = context, opts \\ []) do
    metadata = download_link_preview_metadata(context, opts)

    [
      source_url: context.original_url,
      source_chat: context.chat,
      caption: download_caption(context)
    ]
    |> put_optional_keyword(:download_url, context.download_url)
    |> put_optional_keyword(:thumbnail_url, thumbnail_url_from_metadata(metadata, opts))
    |> put_optional_keyword(:title, metadata_title(metadata))
    |> put_optional_keyword(:description, metadata_description(metadata))
    |> put_optional_keyword(:keywords, metadata_keywords(metadata))
    |> put_optional_keyword(:message_thread_id, message_thread_id(context.message))
  end

  defp download_link_preview_metadata(%DownloadContext{} = context, opts) do
    context
    |> download_link_preview_metadata_url(opts)
    |> fetch_link_preview_metadata()
  end

  defp download_link_preview_metadata_url(
         %DownloadContext{message: message, original_url: original_url},
         opts
       ) do
    preview_url = link_preview_url(message)
    fetch_original? = user_text_caption(message) == ""

    thumbnail_needs_metadata? = Keyword.get(opts, :store_thumbnail_url?, true)

    UrlMetadata.metadata_page_url(original_url, preview_url,
      fetch_original?: fetch_original? or thumbnail_needs_metadata?
    )
  end

  defp fetch_link_preview_metadata(preview_url) when is_binary(preview_url) do
    case LinkPreview.get_metadata(preview_url) do
      {:ok, metadata} -> metadata
      {:error, _reason} -> nil
    end
  end

  defp fetch_link_preview_metadata(_preview_url), do: nil

  defp thumbnail_url_from_metadata(metadata, opts) do
    if Keyword.get(opts, :store_thumbnail_url?, true) do
      metadata_image_url(metadata)
    end
  end

  defp metadata_image_url(%{image_url: image_url}) when is_binary(image_url) and image_url != "",
    do: image_url

  defp metadata_image_url(_metadata), do: nil

  defp metadata_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp metadata_title(_metadata), do: nil

  defp metadata_description(%{description: description})
       when is_binary(description) and description != "",
       do: description

  defp metadata_description(_metadata), do: nil

  defp metadata_keywords(%{keywords: [_ | _] = keywords}), do: keywords
  defp metadata_keywords(_metadata), do: nil

  defp download_message_thumbnail(message) do
    with thumbnail when not is_nil(thumbnail) <- message_thumbnail(message),
         file_id when is_binary(file_id) <- map_get(thumbnail, :file_id),
         {:ok, file} <- ExGram.get_file(file_id),
         {:ok, file_content} <- Telegram.download_file_content(file.file_path) do
      {:ok,
       %DownloadedFile{
         file_name: telegram_file_name(file, file_id, ".jpg"),
         file_content: file_content
       }}
    else
      nil -> {:error, :no_thumbnail}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :missing_thumbnail_file_id}
    end
  end

  defp download_webpage_preview(%DownloadContext{} = context) do
    context.message
    |> link_preview_url()
    |> Kernel.||(context.original_url)
    |> LinkPreview.download_image()
  end

  defp link_preview_url(message) do
    message
    |> map_get(:link_preview_options)
    |> map_get(:url)
  end

  defp message_thumbnail(nil), do: nil

  defp message_thumbnail(message) do
    [
      largest_photo(map_get(message, :photo)),
      map_get(message, :thumbnail),
      map_get(message, :thumb),
      media_thumbnail(map_get(message, :animation)),
      media_thumbnail(map_get(message, :audio)),
      media_thumbnail(map_get(message, :document)),
      media_thumbnail(map_get(message, :video)),
      media_thumbnail(map_get(message, :video_note)),
      media_thumbnail(map_get(message, :sticker)),
      message_thumbnail(map_get(message, :external_reply))
    ]
    |> Enum.find(&thumbnail_file?/1)
  end

  defp media_thumbnail(nil), do: nil

  defp media_thumbnail(media) do
    map_get(media, :thumbnail) || map_get(media, :thumb)
  end

  defp largest_photo([_ | _] = photos), do: List.last(photos)
  defp largest_photo(_photos), do: nil

  defp thumbnail_file?(thumbnail) do
    thumbnail
    |> map_get(:file_id)
    |> is_binary()
  end

  defp map_get(nil, _key), do: nil

  defp map_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp finalize_thumbnail_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    delete_message(context.chat_id, context.progress_message_id)
    FileHelper.write_file(file.file_name, file.file_content, context.original_url)
    GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)

    Logger.info("resource_created source=thumbnail_fallback file_name=#{file.file_name}",
      ansi_color: :green
    )

    :ok
  end

  defp finalize_single_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    delete_message(context.chat_id, context.progress_message_id)
    FileHelper.write_file(file.file_name, file.file_content, context.cache_url)
    GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)

    Logger.info("resource_created source=url_download file_name=#{file.file_name}",
      ansi_color: :green
    )

    :ok
  end

  defp download_caption(%DownloadContext{message: message}), do: user_text_caption(message)

  defp user_text_caption(message) do
    (map_get(message, :text) || map_get(message, :caption))
    |> strip_urls_from_text()
  end

  defp strip_urls_from_text(text) when is_binary(text) do
    text
    |> extract_urls_from_string()
    |> Enum.reduce(text, fn url, acc -> String.replace(acc, url, "") end)
    |> String.trim()
  end

  defp strip_urls_from_text(_text), do: ""

  defp send_message(chat_id, text) do
    ExGram.send_message(chat_id, text)
  end

  defp about_chat_type(%{type: "private"}), do: "dm"
  defp about_chat_type(%{type: "group"}), do: "group"
  defp about_chat_type(%{type: "supergroup"}), do: "group"
  defp about_chat_type(%{type: "channel"}), do: "channel"
  defp about_chat_type(%{type: type}) when is_binary(type), do: type
  defp about_chat_type(_chat), do: "unknown"

  defp about_public_status(%{username: username}) when is_binary(username) do
    if String.trim(username) == "", do: "no", else: "yes"
  end

  defp about_public_status(_chat), do: "no"

  defp about_bot_info, do: ExGram.get_me()

  defp about_bot_admin_status(%{type: "private"}, _bot_info), do: "n/a"

  defp about_bot_admin_status(%{id: chat_id}, bot_info) do
    case about_bot_id(bot_info) do
      nil ->
        "unknown"

      bot_id ->
        case ExGram.get_chat_member(chat_id, bot_id) do
          {:ok, %{status: status}} when status in ["administrator", "creator", "owner"] -> "yes"
          {:ok, %{status: _status}} -> "no"
          {:error, _reason} -> "unknown"
        end
    end
  end

  defp about_bot_admin_status(_chat, _bot_info), do: "unknown"

  defp about_bot_id({:ok, bot_info}), do: Map.get(bot_info, :id)
  defp about_bot_id(_bot_info), do: nil

  defp about_privacy_mode_status({:ok, bot_info}) do
    case Map.get(bot_info, :can_read_all_group_messages) do
      true -> "disabled"
      false -> "enabled"
      _other -> "unknown"
    end
  end

  defp about_privacy_mode_status(_bot_info), do: "unknown"

  defp update_message(chat_id, message_id, texts) when is_list(texts) do
    ExGram.edit_message_text(Enum.join(texts, "\n"), chat_id: chat_id, message_id: message_id)
  end

  defp update_message(chat_id, message_id, text) do
    ExGram.edit_message_text(text, chat_id: chat_id, message_id: message_id)
  end

  defp delete_message(chat_id, message_id) do
    ExGram.delete_message(chat_id, message_id)
  end

  defp bot_send_files(chat_id, files, opts) do
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.get(opts, :source_chat)
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    url_metadata_opts = url_metadata_opts(opts)

    if all_images?(files) and length(files) > 1 do
      bot_send_media_group(
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
        bot_send_downloaded_file(
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

  defp bot_send_downloaded_file(chat_id, %DownloadedFile{} = file, opts) do
    store_download_url? = Keyword.get(opts, :store_download_url?, true)
    download_url = download_url_for_file(file, opts, store_download_url?)

    opts =
      opts
      |> Keyword.delete(:store_download_url?)
      |> Keyword.delete(:download_url)
      |> put_optional_keyword(:download_url, download_url)

    bot_send_file(
      chat_id,
      file.file_name,
      {:file_content, file.file_content, file.file_name},
      opts
    )
  end

  defp download_url_for_file(_file, _opts, false), do: nil

  defp download_url_for_file(%DownloadedFile{} = file, opts, true) do
    Keyword.get(opts, :download_url) || file.download_url
  end

  defp bot_send_filenames(chat_id, filenames, opts) do
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.get(opts, :source_chat)
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    url_metadata_opts = url_metadata_opts(opts)

    if all_images?(filenames) and length(filenames) > 1 do
      bot_send_media_group(
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
        bot_send_file(
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

  defp bot_send_media_group(chat_id, files, opts) do
    source_chat = Keyword.get(opts, :source_chat) || %{id: chat_id}
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)
    url_metadata_opts = url_metadata_opts(opts)

    case Telegram.send_media_group(chat_id, files,
           caption: caption,
           message_thread_id: message_thread_id
         ) do
      {:ok, messages} ->
        Enum.zip(files, messages)
        |> Enum.each(fn
          {{_file_name, content, source_url, download_url, thumbnail_url}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            %{
              image: image_base64,
              caption: caption,
              file_id: file_id,
              url: source_url,
              belongs_to_id: chat_id
            }
            |> put_optional(:download_url, download_url)
            |> put_optional(:thumbnail_url, thumbnail_url)
            |> put_url_metadata_fields(url_metadata_opts)
            |> Map.merge(source_message_fields(source_chat, msg))
            |> safe_typesense_create_photo()

          {{_file_name, content, source_url, download_url}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            %{
              image: image_base64,
              caption: caption,
              file_id: file_id,
              url: source_url,
              belongs_to_id: chat_id
            }
            |> put_optional(:download_url, download_url)
            |> put_url_metadata_fields(url_metadata_opts)
            |> Map.merge(source_message_fields(source_chat, msg))
            |> safe_typesense_create_photo()

          {{_file_name, content, source_url}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            %{
              image: image_base64,
              caption: caption,
              file_id: file_id,
              url: source_url,
              belongs_to_id: chat_id
            }
            |> put_url_metadata_fields(url_metadata_opts)
            |> Map.merge(source_message_fields(source_chat, msg))
            |> safe_typesense_create_photo()

          {{_file_name, content}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            %{
              image: image_base64,
              caption: caption,
              file_id: file_id,
              belongs_to_id: chat_id
            }
            |> put_url_metadata_fields(url_metadata_opts)
            |> Map.merge(source_message_fields(source_chat, msg))
            |> safe_typesense_create_photo()
        end)

      {:error, _reason} ->
        Logger.error("Failed to send media group")

        Enum.each(files, fn
          {file_name, content, source_url, download_url, thumbnail_url} ->
            bot_send_file(
              chat_id,
              file_name,
              content,
              [
                source_url: source_url,
                download_url: download_url,
                thumbnail_url: thumbnail_url,
                source_chat: source_chat,
                caption: caption,
                message_thread_id: message_thread_id
              ] ++ url_metadata_opts
            )

          {file_name, content, source_url, download_url} ->
            bot_send_file(
              chat_id,
              file_name,
              content,
              [
                source_url: source_url,
                download_url: download_url,
                source_chat: source_chat,
                caption: caption,
                message_thread_id: message_thread_id
              ] ++ url_metadata_opts
            )

          {file_name, content, source_url} ->
            bot_send_file(
              chat_id,
              file_name,
              content,
              [
                source_url: source_url,
                source_chat: source_chat,
                caption: caption,
                message_thread_id: message_thread_id
              ] ++ url_metadata_opts
            )

          {file_name, content} ->
            bot_send_file(
              chat_id,
              file_name,
              content,
              [
                source_chat: source_chat,
                caption: caption,
                message_thread_id: message_thread_id
              ] ++ url_metadata_opts
            )
        end)
    end
  end

  defp bot_send_file(chat_id, file_name, file_content, opts) do
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
    url_metadata_opts = url_metadata_opts(opts)

    opts =
      [
        caption: caption,
        source_url: source_url,
        download_url: download_url,
        thumbnail_url: thumbnail_url,
        source_chat: source_chat,
        message_thread_id: message_thread_id
      ] ++ url_metadata_opts

    upload_too_large? = telegram_upload_too_large?(content)

    Logger.debug(
      "Telegram media send started " <>
        "media_type=#{media_type_for_file(file_name)} " <>
        "file_name=#{format_log_value(file_name)} " <>
        "source_url=#{format_log_url(source_url)} " <>
        "download_url=#{format_log_url(download_url)} " <>
        "upload_too_large=#{upload_too_large?}"
    )

    if upload_too_large? do
      handle_telegram_upload_too_large(chat_id, file_name, content, opts)
    else
      do_bot_send_file(
        chat_id,
        file_name,
        content,
        opts
      )
    end
  end

  defp handle_telegram_upload_too_large(chat_id, file_name, content, opts) do
    case file_extension(file_name) do
      ".mp4" ->
        send_oversized_video_preview(chat_id, content, opts)

      _extension ->
        send_message(chat_id, @telegram_file_too_large_message)
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
    url_metadata_opts = url_metadata_opts(opts)

    {prepared_content, video_metadata} = VideoUpload.prepare(content)

    with {:ok, %DownloadedFile{} = preview_file, indexed_thumbnail_url} <-
           oversized_video_preview(prepared_content, video_metadata, source_url, thumbnail_url),
         {:ok, msg} <-
           ExGram.send_photo(
             chat_id,
             {:file_content, preview_file.file_content, preview_file.file_name},
             telegram_send_opts(oversized_video_caption(caption), message_thread_id)
           ),
         file_id when is_binary(file_id) <- get_file_id(msg) do
      %{
        image: Base.encode64(preview_file.file_content),
        caption: caption,
        file_id: file_id,
        media_type: "video",
        url: source_url,
        belongs_to_id: chat_id
      }
      |> put_optional(:download_url, download_url)
      |> put_optional(:thumbnail_url, indexed_thumbnail_url)
      |> put_url_metadata_fields(url_metadata_opts)
      |> Map.merge(source_message_fields(source_chat, msg))
      |> safe_index_photo()

      store_sent_video_preview(preview_file, source_url)
      :ok
    else
      _reason ->
        send_message(chat_id, @telegram_file_too_large_message)
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
        case download_preview_image(thumbnail_url, source_url) do
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

  defp do_bot_send_file(chat_id, file_name, content, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)
    thumbnail_url = Keyword.get(opts, :thumbnail_url)
    source_chat = Keyword.fetch!(opts, :source_chat)
    message_thread_id = Keyword.get(opts, :message_thread_id)
    url_metadata_opts = url_metadata_opts(opts)

    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        {:ok, msg} =
          ExGram.send_photo(chat_id, content, telegram_send_opts(caption, message_thread_id))

        file_id = get_file_id(msg)

        image_base64 =
          encode_file_content(content)

        %{
          image: image_base64,
          caption: caption,
          file_id: file_id,
          url: source_url,
          belongs_to_id: chat_id
        }
        |> put_optional(:download_url, download_url)
        |> put_optional(:thumbnail_url, thumbnail_url)
        |> put_url_metadata_fields(url_metadata_opts)
        |> Map.merge(source_message_fields(source_chat, msg))
        |> safe_index_photo()

      ".mp4" ->
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
              [
                caption: caption,
                source_url: source_url,
                download_url: download_url,
                thumbnail_url: thumbnail_url,
                source_chat: source_chat,
                video_cover: video_cover
              ] ++ url_metadata_opts
            )

            response

          {:error, _reason} = error ->
            error
        end

      ".gif" ->
        ExGram.send_animation(chat_id, content, telegram_send_opts(caption, message_thread_id))

      _ ->
        ExGram.send_document(chat_id, content, telegram_send_opts(caption, message_thread_id))
    end
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
    url_metadata_opts = url_metadata_opts(opts)

    indexed_thumbnail_url =
      if match?({:ok, _cover}, video_cover), do: nil, else: thumbnail_url

    with file_id when is_binary(file_id) <- sent_video_file_id(msg),
         {:ok, %DownloadedFile{} = file} <-
           download_sent_video_preview(msg, source_url, thumbnail_url, video_cover) do
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
      |> put_url_metadata_fields(url_metadata_opts)
      |> Map.merge(source_message_fields(source_chat, msg))
      |> safe_index_photo()

      store_sent_video_preview(file, source_url)
    else
      nil ->
        Logger.warning("Skipping video preview indexing: missing sent video file_id")
        :error

      {:error, _reason} ->
        Logger.warning("Skipping video preview indexing")
        :error
    end
  end

  defp download_sent_video_preview(_msg, _source_url, _thumbnail_url, {:ok, video_cover}) do
    {:ok,
     %DownloadedFile{
       file_name: video_cover.file_name,
       file_content: video_cover.file_content
     }}
  end

  defp download_sent_video_preview(msg, source_url, thumbnail_url, _video_cover) do
    case download_message_thumbnail(msg) do
      {:ok, %DownloadedFile{} = file} -> {:ok, file}
      {:error, _reason} -> download_preview_image(thumbnail_url, source_url)
    end
  end

  defp download_preview_image(thumbnail_url, _source_url) when is_binary(thumbnail_url) do
    WebDownloader.download_file(thumbnail_url)
  end

  defp download_preview_image(_thumbnail_url, source_url),
    do: LinkPreview.download_image(source_url)

  defp store_sent_video_preview(%DownloadedFile{} = file, source_url) do
    cache_url = file.download_url || source_url

    if is_binary(cache_url) do
      FileHelper.write_file(file.file_name, file.file_content, cache_url)
    end
  end

  defp sent_video_file_id(msg) do
    msg
    |> map_get(:video)
    |> map_get(:file_id)
  end

  defp telegram_upload_too_large?({:file_content, file_content, _file_name}) do
    byte_size(file_content) > @telegram_upload_max_file_size
  end

  defp telegram_upload_too_large?({:file, file_path}) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size > @telegram_upload_max_file_size
      {:error, _reason} -> false
    end
  end

  defp file_extension(file_name) do
    Path.extname(file_name)
  end

  defp all_images?(files) when is_list(files) do
    Enum.all?(files, fn
      %DownloadedFile{file_name: file_name} ->
        image_file?(file_name)

      {file_name, _file_content, _source_url} ->
        image_file?(file_name)

      {file_name, _file_content} ->
        image_file?(file_name)

      file_name when is_binary(file_name) ->
        image_file?(file_name)
    end)
  end

  defp image_file?(file_name) do
    file_extension(file_name) in [".png", ".jpg", ".jpeg"]
  end

  defp url_download_media_file?(file_name) do
    file_extension(file_name) in [".png", ".jpg", ".jpeg", ".mp4", ".gif"]
  end

  defp encode_file_content({:file, file}) do
    File.read!(file) |> Base.encode64()
  end

  defp encode_file_content({:file_content, file_content, _file_name}) do
    Base.encode64(file_content)
  end

  defp get_file_id(msg) do
    photos =
      cond do
        is_map(msg) and Map.has_key?(msg, :photo) -> msg.photo
        is_map(msg) and Map.has_key?(msg, "photo") -> msg["photo"]
        true -> nil
      end

    case photos do
      [_ | _] = photos ->
        photo = List.last(photos)
        Map.get(photo, :file_id) || Map.get(photo, "file_id")

      _ ->
        Logger.error("No photo found in the message")
        nil
    end
  end

  defp message_id(message) when is_map(message) do
    Map.get(message, :message_id) || Map.get(message, "message_id")
  end

  defp message_thread_id(message) when is_map(message) do
    Map.get(message, :message_thread_id) || Map.get(message, "message_thread_id")
  end

  defp source_message_fields(chat, message) when is_map(message) do
    source_message_fields(chat, message_id(message), message_thread_id(message))
  end

  defp source_message_fields(chat, message_id) when is_integer(message_id) do
    source_message_fields(chat, message_id, nil)
  end

  defp source_message_fields(_chat, _message), do: %{}

  defp source_message_fields(chat, message_id, message_thread_id) when is_integer(message_id) do
    %{}
    |> put_optional(
      :source_message_url,
      telegram_message_url(chat, message_id, message_thread_id)
    )
  end

  defp source_message_fields(_chat, _message_id, _message_thread_id), do: %{}

  defp telegram_message_url(chat, message_id, message_thread_id) do
    chat_type = map_value(chat, :type)
    username = map_value(chat, :username)
    chat_id = map_value(chat, :id)
    private_channel_id = telegram_private_channel_id(chat_id)

    cond do
      chat_type == "private" ->
        nil

      is_binary(username) and username != "" ->
        "https://t.me/#{username}/#{message_id}"

      private_channel_id && is_integer(message_thread_id) ->
        "https://t.me/c/#{private_channel_id}/#{message_thread_id}/#{message_id}"

      private_channel_id ->
        "https://t.me/c/#{private_channel_id}/#{message_id}"

      true ->
        nil
    end
  end

  defp telegram_private_channel_id(chat_id) do
    chat_id = to_string(chat_id)

    if String.starts_with?(chat_id, "-100") do
      String.replace_prefix(chat_id, "-100", "")
    end
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp map_value(_map, _key), do: nil

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp url_metadata_opts(opts) do
    Keyword.take(opts, [:title, :description, :keywords])
  end

  defp put_url_metadata_fields(map, opts) do
    map
    |> put_optional(:title, Keyword.get(opts, :title))
    |> put_optional(:description, Keyword.get(opts, :description))
    |> put_optional(:keywords, Keyword.get(opts, :keywords))
  end

  defp put_optional_keyword(keyword, _key, nil), do: keyword
  defp put_optional_keyword(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp media_type_for_file(file_name) do
    case file_extension(file_name) do
      ".mp4" -> "video"
      ".png" -> "photo"
      ".jpg" -> "photo"
      ".jpeg" -> "photo"
      _extension -> "file"
    end
  end

  defp format_log_url(nil), do: "nil"

  defp format_log_url(url) when is_binary(url) do
    url
    |> remove_query_and_fragment()
    |> format_log_value()
  end

  defp format_log_url(url), do: format_log_value(inspect(url))

  defp remove_query_and_fragment(url) do
    uri = URI.parse(url)

    %URI{uri | query: nil, fragment: nil}
    |> URI.to_string()
  rescue
    _error -> url
  end

  defp format_log_value(nil), do: "nil"

  defp format_log_value(value) when is_binary(value), do: inspect(value)
  defp format_log_value(value), do: inspect(value)

  defp safe_index_photo(photo_params) do
    case safe_typesense_create_photo(photo_params) do
      nil -> :error
      _ -> :ok
    end
  end

  defp safe_typesense_create_photo(photo_params) do
    Logger.debug(
      "Typesense photo indexing started " <>
        "media_type=#{Map.get(photo_params, :media_type, "photo")} " <>
        "source_url=#{format_log_url(Map.get(photo_params, :url))} " <>
        "download_url=#{format_log_url(Map.get(photo_params, :download_url))}"
    )

    photo_params
    |> PhotoService.create_photo!()
    |> include_created_photo_metadata(photo_params)
  rescue
    error ->
      Logger.error("Typesense create_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, _reason ->
      Logger.error("Typesense create_photo failed", kind: kind)
      nil
  end

  defp include_created_photo_metadata(photo, photo_params) when is_map(photo) do
    Enum.reduce([:file_id, :media_type], photo, fn key, acc ->
      case Map.fetch(photo_params, key) do
        {:ok, value} -> Map.put_new(acc, Atom.to_string(key), value)
        :error -> acc
      end
    end)
  end

  defp include_created_photo_metadata(photo, _photo_params), do: photo

  defp safe_typesense_search_photos(q, opts) do
    PhotoService.search_photos!(q, opts)
  rescue
    error ->
      Logger.error("Typesense search_photos failed: #{Exception.message(error)}")
      []
  catch
    kind, _reason ->
      Logger.error("Typesense search_photos failed", kind: kind)
      []
  end

  defp safe_typesense_search_similar_photos(photo_id, opts) do
    PhotoService.search_similar_photos!(photo_id, opts)
  rescue
    error ->
      Logger.error("Typesense search_similar_photos failed: #{Exception.message(error)}")
      []
  catch
    kind, _reason ->
      Logger.error("Typesense search_similar_photos failed", kind: kind)
      []
  end

  defp login_google(chat) do
    device_code = FileHelper.get_google_device_code(chat.id)

    if present_text?(device_code) do
      exchange_google_device_code(chat, device_code)
    else
      request_google_device_code(chat)
    end
  end

  defp request_google_device_code(chat) do
    case GoogleOAuth2DeviceFlow.get_device_code() do
      {:ok, response} ->
        FileHelper.set_google_device_code(chat.id, response["device_code"])

        send_message(chat.id, """
        Open the following URL in your browser:
        #{response["verification_url"] || response["verification_uri"]}
        Enter code:
        """)

        send_message(chat.id, """
        #{response["user_code"]}
        """)

        send_message(chat.id, """
        After approving access, run `/google_drive_login` again.
        """)

      {:error, {:missing_config, key}} ->
        Logger.error("Google Drive login config missing", key: key)
        send_message(chat.id, missing_google_oauth_config_message(key))

      {:error, %{body: %{"error" => "invalid_client"}}} ->
        Logger.error("Google Drive login config invalid")
        send_message(chat.id, invalid_google_oauth_client_message())

      {:error, _error} ->
        Logger.error("Failed to get Google Drive login code")
        send_message(chat.id, "Failed to get Google Drive login code.")
    end
  end

  defp exchange_google_device_code(chat, device_code) do
    case GoogleOAuth2DeviceFlow.exchange_device_code_for_token(device_code) do
      {:ok, %{"access_token" => access_token}} when is_binary(access_token) ->
        FileHelper.set_google_access_token(chat.id, access_token)
        FileHelper.set_google_device_code(chat.id, "")
        send_message(chat.id, "Google Drive connected.")

      {:error, %{body: %{"error" => "authorization_pending"}}} ->
        send_message(chat.id, """
        Google authorization is not complete yet.

        Approve access in your browser, then run `/google_drive_login` again.
        """)

      {:error, {:missing_config, key}} ->
        Logger.error("Google Drive login config missing", key: key)
        send_message(chat.id, missing_google_oauth_config_message(key))

      {:error, %{body: %{"error" => "invalid_client"}}} ->
        FileHelper.set_google_device_code(chat.id, "")
        Logger.error("Google Drive login config invalid")
        send_message(chat.id, invalid_google_oauth_client_message())

      {:error, %{body: %{"error" => error}}} when error in ["access_denied", "expired_token"] ->
        FileHelper.set_google_device_code(chat.id, "")

        send_message(chat.id, """
        Google Drive login code expired or was denied.

        Run `/google_drive_login` to get a new code.
        """)

      {:error, _error} ->
        Logger.error("Failed to connect Google Drive")

        send_message(chat.id, """
        Failed to connect Google Drive.

        Please run `/google_drive_login` again.
        """)
    end
  end

  defp missing_google_oauth_config_message(:google_oauth_client_id) do
    """
    Google Drive login is not configured.

    Ask the bot operator to set GOOGLE_OAUTH_CLIENT_ID, then run `/google_drive_login` again.
    """
  end

  defp missing_google_oauth_config_message(:google_oauth_client_secret) do
    """
    Google Drive login is not configured.

    Ask the bot operator to set GOOGLE_OAUTH_CLIENT_SECRET, then run `/google_drive_login` again.
    """
  end

  defp invalid_google_oauth_client_message do
    """
    Google Drive login configuration is invalid.

    Ask the bot operator to verify GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET match a Google OAuth client whose application type is TVs and Limited Input devices.

    After fixing the configuration, run `/google_drive_login` again.
    """
  end

  defp google_drive_login_permission(%{type: "private"}, _from), do: :ok

  defp google_drive_login_permission(%{type: type} = chat, from)
       when type == "group" or type == "supergroup" do
    {:ok, members} = ExGram.get_chat_administrators(chat.id)

    cond do
      Map.get(from || %{}, :is_bot) ->
        :ok

      Enum.any?(members, &(&1.user.id == Map.get(from || %{}, :id))) ->
        :ok

      true ->
        {:error, :not_admin}
    end
  end

  defp google_drive_login_permission(_chat, _from), do: {:error, :unsupported_chat}

  defp normalize_command_text(text) when is_binary(text), do: String.trim(text)
  defp normalize_command_text(_text), do: ""

  defp present_text?(text) when is_binary(text), do: String.trim(text) != ""
  defp present_text?(_text), do: false

  defp handle_delete_command(chat_id, message_id, reply_to_message) do
    case reply_to_message do
      %{photo: nil} ->
        delete_message(chat_id, reply_to_message.message_id)

      %{photo: photo} ->
        photo
        |> Enum.map(& &1.file_id)
        |> PhotoService.delete_photos()

        delete_message(chat_id, reply_to_message.message_id)

      _ ->
        send_message(chat_id, "reply a message with /delete command.")
    end

    delete_message(chat_id, message_id)
  end

  defp handle_detail_command(chat_id, reply_to_message, file_id) do
    case safe_typesense_get_photo(file_id, chat_id) do
      nil ->
        send_message(chat_id, "Media details not found.")

      photo ->
        send_message(chat_id, detail_message(reply_to_message, photo))
    end
  end

  defp detail_media_file_id(%{photo: [_ | _] = photos}) do
    photos |> List.last() |> Map.get(:file_id)
  end

  defp detail_media_file_id(%{video: %{file_id: file_id}}), do: file_id
  defp detail_media_file_id(_reply_to_message), do: nil

  defp detail_message(reply_to_message, photo) do
    [
      detail_line("Message URL", Map.get(photo, "source_message_url")),
      detail_line("Original URL", Map.get(photo, "url")),
      detail_line("Caption", Map.get(photo, "caption")),
      detail_line("Title", Map.get(photo, "title")),
      detail_line("Description", Map.get(photo, "description")),
      detail_line("Keywords", detail_keywords(Map.get(photo, "keywords"))),
      detail_line("Saved at", saved_at(photo, reply_to_message))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp detail_line(_label, nil), do: nil
  defp detail_line(_label, ""), do: nil
  defp detail_line(label, value), do: "#{label}: #{value}"

  defp detail_keywords([_ | _] = keywords), do: Enum.join(keywords, ", ")
  defp detail_keywords(_keywords), do: nil

  defp saved_at(photo, reply_to_message) do
    format_unix_time(Map.get(photo, "inserted_at") || Map.get(reply_to_message, :date))
  end

  defp format_unix_time(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_unix_time(_timestamp), do: nil

  defp safe_typesense_get_photo(file_id, belongs_to_id) do
    PhotoService.get_photo(file_id, belongs_to_id)
  rescue
    error ->
      Logger.error("Typesense get_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, _reason ->
      Logger.error("Typesense get_photo failed", kind: kind)
      nil
  end
end
