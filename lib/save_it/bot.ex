defmodule SaveIt.Bot do
  @moduledoc false

  require Logger

  import SaveIt.SmallHelper.UrlHelper, only: [direct_media_url?: 1]

  alias SaveIt.DownloadContext
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive
  alias SaveIt.GoogleOAuth2DeviceFlow

  alias SaveIt.PhotoService

  alias SmallSdk.BadNews
  alias SmallSdk.Cobalt
  alias SmallSdk.HlsDownloader
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

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")

  command("search", description: "Search photos")
  command("similar", description: "Find similar photos")
  command("delete", description: "Delete message")
  command("detail", description: "Show photo details")

  command("login", description: "Login")
  command("code", description: "Get code for login")
  command("folder", description: "Update Google Drive folder ID")

  command("about", description: "Know more about this bot")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot, do: @bot

  def handle({:command, :start, _msg}, context) do
    answer(context, "Hi! I'm a bot that can download images and videos, just give me a link.")
  end

  def handle({:command, :about, _msg}, context) do
    answer(context, """
    SaveIt can download images and videos, just give me a link.

    Created by @ThaddeusJiang, powered by Cobalt, Typesense, and Elixir.Access

    Give a star ⭐ if you like it, https://github.com/ThaddeusJiang/save_it
    """)
  end

  def handle({:command, :code, %{chat: chat}}, _context) do
    case GoogleOAuth2DeviceFlow.get_device_code() do
      {:ok, response} ->
        FileHelper.set_google_device_code(chat.id, response["device_code"])
        # SettingsStore.update_google_device_code(msg.chat.id, response["device_code"])

        send_message(chat.id, """
        Open the following URL in your browser:
        #{response["verification_url"]}
        Enter code: 👇
        """)

        send_message(chat.id, """
        #{response["user_code"]}
        """)

        send_message(chat.id, """
        Run `/login` after you have logged in.
        """)

      {:error, error} ->
        Logger.error("Failed to get device code: #{inspect(error)}")
        send_message(chat.id, "Failed to get device code")
    end
  end

  def handle({:command, :login, %{chat: chat, from: from}}, _context) do
    case chat.type do
      "private" ->
        login_google(chat)

      x when x == "group" or x == "supergroup" ->
        {:ok, members} = ExGram.get_chat_administrators(chat.id)

        cond do
          from.is_bot ->
            login_google(chat)

          # 其他语言写法 fn member -> member.user.id == from.id end
          Enum.any?(members, &(&1.user.id == from.id)) ->
            login_google(chat)

          true ->
            send_message(chat.id, "You are not an administrator, you can't login.")
        end

      _ ->
        send_message(chat.id, "You can't login in this chat.")
    end
  end

  def handle({:command, :folder, %{chat: chat, text: text}}, _context) do
    case text do
      nil ->
        send_message(chat.id, "Please provide a folder ID.")

      "" ->
        send_message(chat.id, "Please provide a folder ID.")

      _ ->
        FileHelper.set_google_drive_folder_id(chat.id, text)
        send_message(chat.id, "Folder ID set successfully.")
    end
  end

  def handle({:command, :search, %{chat: chat, text: nil}}, _context) do
    send_message(chat.id, "What do you want to search? animal, food, etc.")
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

  def handle({:command, :similar, %{chat: chat, photo: nil}}, _context) do
    send_message(chat.id, "Upload a photo with /similar for finding similar photos.")
  end

  def handle({:command, :detail, %{chat: chat, reply_to_message: nil}}, _context) do
    send_message(chat.id, "reply a photo with /detail command.")
  end

  def handle({:command, :detail, %{chat: chat, reply_to_message: reply_to_message}}, _context) do
    case Map.get(reply_to_message, :photo) do
      [_ | _] = photos ->
        handle_detail_command(chat.id, reply_to_message, photos)

      _ ->
        send_message(chat.id, "reply a photo with /detail command.")
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
  # caption: contains /similar or /search -> search similar photos; otherwise, find same photos
  def handle({:message, %{chat: chat, photo: [_ | _] = photos} = message}, _ctx) do
    handle_uploaded_photo(chat.id, Map.get(message, :caption), photos)
  end

  def handle({:message, %{chat: chat, video: %{file_id: _file_id} = video} = message}, _ctx) do
    handle_uploaded_video(chat.id, Map.get(message, :caption), video)
  end

  def handle({:text, text, %{chat: chat, message_id: message_id}}, _context) do
    urls = extract_urls_from_string(text)

    case urls do
      [] ->
        :ok

      _ ->
        has_success? =
          urls
          |> Enum.map(&process_url(chat.id, &1))
          |> Enum.any?(&(&1 == :ok))

        if has_success? do
          delete_message(chat.id, message_id)
        end
    end
  end

  def handle({:edited_message, %{photo: nil}}, _context) do
    Logger.warning("this is an edited message, ignore it")
    # Edited search commands are ignored for now.
    {:ok, nil}
  end

  def handle({:edited_message, %{chat: chat, caption: caption, photo: photos}}, _context) do
    file_id = photos |> List.last() |> Map.get(:file_id)
    PhotoService.update_photo_caption!(file_id, chat.id, caption)
  end

  def handle({:update, _update}, _context) do
    Logger.warning("this is an update, ignore it")
    {:ok, nil}
  end

  def handle({:message, _message}, _context) do
    Logger.warning("this is a message, ignore it")
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

      {:error, reason} ->
        Logger.warning(
          "Failed to send similar media group, falling back to individual media: #{inspect(reason)}"
        )

        Enum.each(similar_photos, &send_similar_media(chat_id, &1))
        :ok
    end
  end

  defp send_similar_media(chat_id, media) do
    case send_saved_media(chat_id, media) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Skipping unavailable similar media file_id=#{inspect(media["file_id"])}: #{inspect(reason)}"
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

  defp handle_uploaded_photo(chat_id, caption, photos) do
    photo = List.last(photos)
    file = ExGram.get_file!(photo.file_id)
    file_content = Telegram.download_file_content!(file.file_path)
    file_name = telegram_file_name(file, photo.file_id, ".jpg")

    FileHelper.write_file(file_name, file_content, telegram_cache_key("photo", file.file_id))
    GoogleDrive.upload_file_content(chat_id, file_content, file_name)

    %{
      image: Base.encode64(file_content),
      caption: searchable_caption(caption),
      file_id: file.file_id,
      media_type: "photo",
      belongs_to_id: chat_id
    }
    |> safe_typesense_create_photo()
    |> answer_similar_for_uploaded_media(chat_id, caption)
  end

  defp handle_uploaded_video(chat_id, caption, video) do
    typesense_photo =
      video
      |> video_thumbnail()
      |> create_video_thumbnail_index(chat_id, caption, video.file_id)

    store_uploaded_video_file(chat_id, video)
    answer_similar_for_uploaded_media(typesense_photo, chat_id, caption)
  end

  defp create_video_thumbnail_index(nil, _chat_id, _caption, _file_id), do: nil

  defp create_video_thumbnail_index(thumbnail, chat_id, caption, file_id) do
    thumbnail_file = ExGram.get_file!(thumbnail.file_id)
    thumbnail_content = Telegram.download_file_content!(thumbnail_file.file_path)

    safe_typesense_create_photo(%{
      image: Base.encode64(thumbnail_content),
      caption: searchable_caption(caption),
      file_id: file_id,
      media_type: "video",
      belongs_to_id: chat_id
    })
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

  defp handle_uploaded_video_file_error(reason) do
    Logger.warning("Skipping local backup for Telegram video: #{inspect(reason)}")
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
    if search_command_caption?(caption), do: "", else: caption || ""
  end

  defp search_command_caption?(caption) when is_binary(caption) do
    String.contains?(caption, ["/similar", "/search"])
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
      supports_streaming: true,
      show_caption_above_media: true
    )
  end

  defp send_saved_media(chat_id, media) do
    ExGram.send_photo(chat_id, media["file_id"],
      caption: media["caption"],
      show_caption_above_media: true
    )
  end

  defp saved_media_group_input(%{"media_type" => "video"} = media) do
    %ExGram.Model.InputMediaVideo{
      type: "video",
      media: media["file_id"],
      caption: media["caption"],
      supports_streaming: true,
      show_caption_above_media: true
    }
  end

  defp saved_media_group_input(media) do
    %ExGram.Model.InputMediaPhoto{
      type: "photo",
      media: media["file_id"],
      caption: media["caption"],
      show_caption_above_media: true
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

  defp process_url(chat_id, url) do
    {:ok, progress_message} = send_message(chat_id, Enum.at(@progress, 0))

    context = %DownloadContext{
      chat_id: chat_id,
      progress_message_id: progress_message.message_id,
      original_url: url
    }

    case get_download_url(url) do
      {:ok, m3u8_url, :hls} ->
        handle_hls_download(%{context | cache_url: url}, m3u8_url)

      {:ok, purge_url, download_urls} ->
        handle_multi_file_download(%{context | purge_url: purge_url}, download_urls)

      {:ok, download_url} ->
        handle_single_file_download(%{
          context
          | download_url: download_url,
            cache_url: download_url
        })

      {:error, _} ->
        update_message(chat_id, context.progress_message_id, "💔 Failed to get download URL.")
        :error
    end
  end

  defp handle_hls_download(%DownloadContext{} = context, m3u8_url) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case HlsDownloader.download(m3u8_url) do
      {:ok, %DownloadedFile{} = file} ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))
        bot_send_downloaded_file(context.chat_id, file)
        finalize_single_download(context, file)

      {:error, _reason} ->
        update_message(
          context.chat_id,
          context.progress_message_id,
          "💔 Failed downloading HLS video."
        )

        :error
    end
  end

  defp handle_multi_file_download(%DownloadContext{} = context, download_urls) do
    case FileHelper.get_downloaded_files(context.purge_url) do
      nil ->
        download_and_store_files(context, download_urls)

      downloaded_files ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))
        bot_send_filenames(context.chat_id, downloaded_files, source_url: context.original_url)
        delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_files(%DownloadContext{} = context, download_urls) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_files(download_urls) do
      {:ok, files} ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))
        bot_send_files(context.chat_id, files, source_url: context.original_url)
        delete_message(context.chat_id, context.progress_message_id)
        FileHelper.write_folder(context.purge_url, files)
        GoogleDrive.upload_files(context.chat_id, files)
        :ok

      _ ->
        update_message(context.chat_id, context.progress_message_id, "💔 Failed downloading file.")
        :error
    end
  end

  defp handle_single_file_download(%DownloadContext{} = context) do
    case FileHelper.get_downloaded_file(context.download_url) do
      nil ->
        download_and_store_file(context)

      downloaded_file ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_file(context.chat_id, downloaded_file, {:file, downloaded_file},
          source_url: context.original_url,
          download_url: context.download_url
        )

        delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_file(%DownloadContext{} = context) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_file(context.download_url) do
      {:ok, %DownloadedFile{} = file} ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))
        bot_send_downloaded_file(context.chat_id, file, source_url: context.original_url)
        finalize_single_download(context, file)

      _ ->
        update_message(context.chat_id, context.progress_message_id, "💔 Failed downloading file.")
        :error
    end
  end

  defp finalize_single_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    delete_message(context.chat_id, context.progress_message_id)
    FileHelper.write_file(file.file_name, file.file_content, context.cache_url)
    GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)
    :ok
  end

  defp send_message(chat_id, text) do
    ExGram.send_message(chat_id, text)
  end

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

    if all_images?(files) and length(files) > 1 do
      bot_send_media_group(
        chat_id,
        Enum.map(files, fn %DownloadedFile{} = file ->
          {file.file_name, {:file_content, file.file_content, file.file_name}, source_url,
           file.download_url}
        end)
      )
    else
      Enum.each(files, fn %DownloadedFile{} = file ->
        bot_send_downloaded_file(chat_id, file, source_url: source_url)
      end)
    end
  end

  defp bot_send_downloaded_file(chat_id, %DownloadedFile{} = file, opts \\ []) do
    bot_send_file(
      chat_id,
      file.file_name,
      {:file_content, file.file_content, file.file_name},
      Keyword.put_new(opts, :download_url, file.download_url)
    )
  end

  defp bot_send_filenames(chat_id, filenames, opts) do
    source_url = Keyword.get(opts, :source_url)

    if all_images?(filenames) and length(filenames) > 1 do
      bot_send_media_group(
        chat_id,
        Enum.map(filenames, fn filename -> {filename, {:file, filename}, source_url} end)
      )
    else
      Enum.each(filenames, fn filename ->
        bot_send_file(chat_id, filename, {:file, filename}, source_url: source_url)
      end)
    end
  end

  defp bot_send_media_group(chat_id, files) do
    case Telegram.send_media_group(chat_id, files) do
      {:ok, messages} ->
        Enum.zip(files, messages)
        |> Enum.each(fn
          {{_file_name, content, source_url, download_url}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            PhotoService.create_photo!(%{
              image: image_base64,
              caption: "",
              file_id: file_id,
              url: source_url,
              download_url: download_url,
              belongs_to_id: chat_id
            })

          {{_file_name, content, source_url}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            PhotoService.create_photo!(%{
              image: image_base64,
              caption: "",
              file_id: file_id,
              url: source_url,
              belongs_to_id: chat_id
            })

          {{_file_name, content}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            PhotoService.create_photo!(%{
              image: image_base64,
              caption: "",
              file_id: file_id,
              belongs_to_id: chat_id
            })
        end)

      {:error, reason} ->
        Logger.error("Failed to send media group: #{inspect(reason)}")

        Enum.each(files, fn
          {file_name, content, source_url, download_url} ->
            bot_send_file(chat_id, file_name, content,
              source_url: source_url,
              download_url: download_url
            )

          {file_name, content, source_url} ->
            bot_send_file(chat_id, file_name, content, source_url: source_url)

          {file_name, content} ->
            bot_send_file(chat_id, file_name, content)
        end)
    end
  end

  defp bot_send_file(chat_id, file_name, file_content, opts \\ []) do
    content =
      case file_content do
        {:file, file} -> {:file, file}
        {:file_content, file_content, file_name} -> {:file_content, file_content, file_name}
      end

    caption = Keyword.get(opts, :caption, "")
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)

    if telegram_upload_too_large?(content) do
      send_message(chat_id, @telegram_file_too_large_message)
      {:error, :telegram_file_too_large}
    else
      do_bot_send_file(chat_id, file_name, content,
        caption: caption,
        source_url: source_url,
        download_url: download_url
      )
    end
  end

  defp do_bot_send_file(chat_id, file_name, content, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)

    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        {:ok, msg} = ExGram.send_photo(chat_id, content, caption: caption)

        file_id = get_file_id(msg)

        image_base64 =
          encode_file_content(content)

        safe_index_photo(%{
          image: image_base64,
          caption: caption,
          file_id: file_id,
          url: source_url,
          download_url: download_url,
          belongs_to_id: chat_id
        })

      ".mp4" ->
        ExGram.send_video(chat_id, content, supports_streaming: true, caption: caption)

      ".gif" ->
        ExGram.send_animation(chat_id, content, caption: caption)

      _ ->
        ExGram.send_document(chat_id, content, caption: caption)
    end
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

  defp safe_index_photo(photo_params) do
    case safe_typesense_create_photo(photo_params) do
      nil -> :error
      _ -> :ok
    end
  end

  defp safe_typesense_create_photo(photo_params) do
    photo_params
    |> PhotoService.create_photo!()
    |> include_created_photo_metadata(photo_params)
  rescue
    error ->
      Logger.error("Typesense create_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, reason ->
      Logger.error("Typesense create_photo failed: #{inspect({kind, reason})}")
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
    kind, reason ->
      Logger.error("Typesense search_photos failed: #{inspect({kind, reason})}")
      []
  end

  defp safe_typesense_search_similar_photos(photo_id, opts) do
    PhotoService.search_similar_photos!(photo_id, opts)
  rescue
    error ->
      Logger.error("Typesense search_similar_photos failed: #{Exception.message(error)}")
      []
  catch
    kind, reason ->
      Logger.error("Typesense search_similar_photos failed: #{inspect({kind, reason})}")
      []
  end

  defp login_google(chat) do
    device_code = FileHelper.get_google_device_code(chat.id)

    case GoogleOAuth2DeviceFlow.exchange_device_code_for_token(device_code) do
      {:ok, body} ->
        FileHelper.set_google_access_token(chat.id, body["access_token"])
        send_message(chat.id, "Successfully logged in!")

      {:error, error} ->
        Logger.error("Failed to log in: #{inspect(error)}")

        send_message(chat.id, """
        Failed to log in.

        Please run `/code` to get a new code, then run `/login` again.
        """)
    end
  end

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

  defp handle_detail_command(chat_id, reply_to_message, photos) do
    file_id = photos |> List.last() |> Map.get(:file_id)

    case safe_typesense_get_photo(file_id, chat_id) do
      nil ->
        send_message(chat_id, "Photo details not found.")

      photo ->
        send_message(chat_id, detail_message(reply_to_message, photo, file_id))
    end
  end

  defp detail_message(reply_to_message, photo, file_id) do
    [
      "Sent at: #{format_unix_time(Map.get(reply_to_message, :date))}",
      "Original URL: #{detail_value(photo, "url")}",
      "Download URL: #{detail_value(photo, "download_url")}",
      "File ID: #{file_id}",
      "Typesense ID: #{detail_value(photo, "id")}"
    ]
    |> Enum.join("\n")
  end

  defp detail_value(photo, key) do
    case Map.get(photo, key) do
      value when is_binary(value) and value != "" -> value
      _ -> "N/A"
    end
  end

  defp format_unix_time(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_unix_time(_timestamp), do: "N/A"

  defp safe_typesense_get_photo(file_id, belongs_to_id) do
    PhotoService.get_photo(file_id, belongs_to_id)
  rescue
    error ->
      Logger.error("Typesense get_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, reason ->
      Logger.error("Typesense get_photo failed: #{inspect({kind, reason})}")
      nil
  end
end
