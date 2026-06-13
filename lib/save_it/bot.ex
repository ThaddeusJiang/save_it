defmodule SaveIt.Bot do
  @moduledoc false

  require Logger

  import SaveIt.SmallHelper.UrlHelper, only: [direct_media_url?: 1]

  alias SaveIt.DownloadContext
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive
  alias SaveIt.GoogleOAuth2DeviceFlow
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

      {:error, _error} ->
        Logger.error("Failed to get device code")
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
    handle_uploaded_photo(message, chat, Map.get(message, :caption), photos)
  end

  def handle({:message, %{chat: chat, video: %{file_id: _file_id} = video} = message}, _ctx) do
    handle_uploaded_video(message, chat, Map.get(message, :caption), video)
  end

  def handle({:text, text, %{chat: chat, message_id: message_id} = message}, _context) do
    urls = extract_urls_from_string(text)
    message = Map.put_new(message, :text, text)

    case urls do
      [] ->
        :ok

      _ ->
        has_success? =
          urls
          |> Enum.map(&process_url(chat, &1, message))
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

      {:error, _reason} ->
        Logger.warning(
          "Failed to send similar media group, falling back to individual media",
          kind: :telegram_media_group_failed
        )

        Enum.each(similar_photos, &send_similar_media(chat_id, &1))
        :ok
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
    |> Map.merge(source_message_fields(chat, message_id(message)))
    |> safe_typesense_create_photo()
    |> answer_similar_for_uploaded_media(chat.id, caption)
  end

  defp handle_uploaded_video(message, chat, caption, video) do
    typesense_photo =
      video
      |> video_thumbnail()
      |> create_video_thumbnail_index(chat, message_id(message), caption, video.file_id)

    store_uploaded_video_file(chat.id, video)
    answer_similar_for_uploaded_media(typesense_photo, chat.id, caption)
  end

  defp create_video_thumbnail_index(nil, _chat, _message_id, _caption, _file_id), do: nil

  defp create_video_thumbnail_index(thumbnail, chat, message_id, caption, file_id) do
    thumbnail_file = ExGram.get_file!(thumbnail.file_id)
    thumbnail_content = Telegram.download_file_content!(thumbnail_file.file_path)

    %{
      image: Base.encode64(thumbnail_content),
      caption: searchable_caption(caption),
      file_id: file_id,
      media_type: "video",
      belongs_to_id: chat.id
    }
    |> Map.merge(source_message_fields(chat, message_id))
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
        handle_hls_download(%{context | cache_url: url}, m3u8_url)

      {:ok, purge_url, download_urls} ->
        handle_multi_file_download(%{context | purge_url: purge_url}, download_urls)

      {:ok, download_url} ->
        handle_single_file_download(%{
          context
          | download_url: download_url,
            cache_url: download_url
        })

      {:error, reason} ->
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
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_downloaded_file(context.chat_id, file,
          source_url: context.original_url,
          source_chat: context.chat,
          caption: download_caption(context)
        )

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

        bot_send_filenames(context.chat_id, downloaded_files,
          source_url: context.original_url,
          source_chat: context.chat,
          caption: download_caption(context)
        )

        delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_files(%DownloadContext{} = context, download_urls) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_files(download_urls) do
      {:ok, files} ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

        bot_send_files(context.chat_id, files,
          source_url: context.original_url,
          source_chat: context.chat,
          caption: download_caption(context)
        )

        delete_message(context.chat_id, context.progress_message_id)
        FileHelper.write_folder(context.purge_url, files)
        GoogleDrive.upload_files(context.chat_id, files)
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

        bot_send_file(context.chat_id, downloaded_file, {:file, downloaded_file},
          source_url: context.original_url,
          source_chat: context.chat,
          caption: download_caption(context)
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

        bot_send_downloaded_file(context.chat_id, file,
          source_url: context.original_url,
          source_chat: context.chat,
          caption: download_caption(context)
        )

        finalize_single_download(context, file)

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading file.", reason)
    end
  end

  defp handle_download_failure(%DownloadContext{} = context, failure_message, _failure_reason) do
    case download_fallback_thumbnail(context) do
      {:ok, %DownloadedFile{} = file, source} ->
        log_thumbnail_fallback_success(source)
        save_thumbnail_fallback(context, file)

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

  defp save_thumbnail_fallback(%DownloadContext{} = context, %DownloadedFile{} = file) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))

    bot_send_downloaded_file(context.chat_id, file,
      source_url: context.original_url,
      source_chat: context.chat,
      caption: download_caption(context)
    )

    finalize_thumbnail_download(context, file)
  end

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
    :ok
  end

  defp finalize_single_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    delete_message(context.chat_id, context.progress_message_id)
    FileHelper.write_file(file.file_name, file.file_content, context.cache_url)
    GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)
    :ok
  end

  defp download_caption(%DownloadContext{message: message, original_url: original_url}) do
    case user_text_caption(message) do
      caption when is_binary(caption) and caption != "" ->
        caption

      _ ->
        link_preview_description(message, original_url)
    end
  end

  defp user_text_caption(message) do
    message
    |> map_get(:text)
    |> strip_urls_from_text()
  end

  defp strip_urls_from_text(text) when is_binary(text) do
    text
    |> extract_urls_from_string()
    |> Enum.reduce(text, fn url, acc -> String.replace(acc, url, "") end)
    |> String.trim()
  end

  defp strip_urls_from_text(_text), do: ""

  defp link_preview_description(message, original_url) do
    (link_preview_url(message) || original_url)
    |> case do
      url when is_binary(url) -> LinkPreview.get_description(url)
      _ -> {:error, :missing_preview_url}
    end
    |> case do
      {:ok, description} -> description
      {:error, _reason} -> ""
    end
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
    source_chat = Keyword.get(opts, :source_chat)
    caption = Keyword.get(opts, :caption, "")

    if all_images?(files) and length(files) > 1 do
      bot_send_media_group(
        chat_id,
        Enum.map(files, fn %DownloadedFile{} = file ->
          {file.file_name, {:file_content, file.file_content, file.file_name}, source_url}
        end),
        source_chat: source_chat,
        caption: caption
      )
    else
      Enum.each(files, fn %DownloadedFile{} = file ->
        bot_send_downloaded_file(chat_id, file,
          source_url: source_url,
          source_chat: source_chat,
          caption: caption
        )
      end)
    end
  end

  defp bot_send_downloaded_file(chat_id, %DownloadedFile{} = file, opts) do
    bot_send_file(
      chat_id,
      file.file_name,
      {:file_content, file.file_content, file.file_name},
      opts
    )
  end

  defp bot_send_filenames(chat_id, filenames, opts) do
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.get(opts, :source_chat)
    caption = Keyword.get(opts, :caption, "")

    if all_images?(filenames) and length(filenames) > 1 do
      bot_send_media_group(
        chat_id,
        Enum.map(filenames, fn filename -> {filename, {:file, filename}, source_url} end),
        source_chat: source_chat,
        caption: caption
      )
    else
      Enum.each(filenames, fn filename ->
        bot_send_file(chat_id, filename, {:file, filename},
          source_url: source_url,
          source_chat: source_chat,
          caption: caption
        )
      end)
    end
  end

  defp bot_send_media_group(chat_id, files, opts) do
    source_chat = Keyword.get(opts, :source_chat) || %{id: chat_id}
    caption = Keyword.get(opts, :caption, "")

    case Telegram.send_media_group(chat_id, files, caption: caption) do
      {:ok, messages} ->
        Enum.zip(files, messages)
        |> Enum.each(fn
          {{_file_name, content, source_url, _download_url}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            %{
              image: image_base64,
              caption: caption,
              file_id: file_id,
              url: source_url,
              belongs_to_id: chat_id
            }
            |> Map.merge(source_message_fields(source_chat, message_id(msg)))
            |> PhotoService.create_photo!()

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
            |> Map.merge(source_message_fields(source_chat, message_id(msg)))
            |> PhotoService.create_photo!()

          {{_file_name, content}, msg} ->
            file_id = get_file_id(msg)
            image_base64 = encode_file_content(content)

            %{
              image: image_base64,
              caption: caption,
              file_id: file_id,
              belongs_to_id: chat_id
            }
            |> Map.merge(source_message_fields(source_chat, message_id(msg)))
            |> PhotoService.create_photo!()
        end)

      {:error, _reason} ->
        Logger.error("Failed to send media group")

        Enum.each(files, fn
          {file_name, content, source_url, _download_url} ->
            bot_send_file(chat_id, file_name, content,
              source_url: source_url,
              source_chat: source_chat,
              caption: caption
            )

          {file_name, content, source_url} ->
            bot_send_file(chat_id, file_name, content,
              source_url: source_url,
              source_chat: source_chat,
              caption: caption
            )

          {file_name, content} ->
            bot_send_file(chat_id, file_name, content, source_chat: source_chat, caption: caption)
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
    source_chat = Keyword.get(opts, :source_chat) || %{id: chat_id}

    if telegram_upload_too_large?(content) do
      send_message(chat_id, @telegram_file_too_large_message)
      {:error, :telegram_file_too_large}
    else
      do_bot_send_file(chat_id, file_name, content,
        caption: caption,
        source_url: source_url,
        source_chat: source_chat
      )
    end
  end

  defp do_bot_send_file(chat_id, file_name, content, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.fetch!(opts, :source_chat)

    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        {:ok, msg} = ExGram.send_photo(chat_id, content, caption: caption)

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
        |> Map.merge(source_message_fields(source_chat, message_id(msg)))
        |> safe_index_photo()

      ".mp4" ->
        {prepared_content, video_metadata} = VideoUpload.prepare(content)

        case ExGram.send_video(
               chat_id,
               prepared_content,
               video_send_opts(caption, video_metadata)
             ) do
          {:ok, msg} = response ->
            index_sent_video_preview(chat_id, msg,
              caption: caption,
              source_url: source_url,
              source_chat: source_chat
            )

            response

          {:error, _reason} = error ->
            error
        end

      ".gif" ->
        ExGram.send_animation(chat_id, content, caption: caption)

      _ ->
        ExGram.send_document(chat_id, content, caption: caption)
    end
  end

  defp video_send_opts(caption, video_metadata) do
    [supports_streaming: true, caption: caption]
    |> maybe_put_video_metadata(:width, video_metadata)
    |> maybe_put_video_metadata(:height, video_metadata)
    |> maybe_put_video_metadata(:duration, video_metadata)
  end

  defp maybe_put_video_metadata(opts, key, metadata) when is_map(metadata) do
    case Map.get(metadata, key) do
      value when is_integer(value) and value > 0 -> Keyword.put(opts, key, value)
      _ -> opts
    end
  end

  defp index_sent_video_preview(chat_id, msg, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    source_chat = Keyword.fetch!(opts, :source_chat)

    with file_id when is_binary(file_id) <- sent_video_file_id(msg),
         {:ok, %DownloadedFile{} = file} <- download_sent_video_preview(msg, source_url) do
      %{
        image: Base.encode64(file.file_content),
        caption: caption,
        file_id: file_id,
        media_type: "video",
        url: source_url,
        belongs_to_id: chat_id
      }
      |> Map.merge(source_message_fields(source_chat, message_id(msg)))
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

  defp download_sent_video_preview(msg, source_url) do
    case download_message_thumbnail(msg) do
      {:ok, %DownloadedFile{} = file} -> {:ok, file}
      {:error, _reason} -> LinkPreview.download_image(source_url)
    end
  end

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

  defp message_id(_message), do: nil

  defp source_message_fields(chat, message_id) when is_integer(message_id) do
    %{}
    |> Map.put(:source_message_id, message_id)
    |> put_optional(:source_message_url, telegram_message_url(chat, message_id))
  end

  defp source_message_fields(_chat, _message_id), do: %{}

  defp telegram_message_url(chat, message_id) do
    username = map_value(chat, :username)
    chat_id = map_value(chat, :id)
    private_channel_id = telegram_private_channel_id(chat_id)

    cond do
      is_binary(username) and username != "" ->
        "https://t.me/#{username}/#{message_id}"

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

    case GoogleOAuth2DeviceFlow.exchange_device_code_for_token(device_code) do
      {:ok, body} ->
        FileHelper.set_google_access_token(chat.id, body["access_token"])
        send_message(chat.id, "Successfully logged in!")

      {:error, _error} ->
        Logger.error("Failed to log in")

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
        send_message(chat_id, detail_message(reply_to_message, photo))
    end
  end

  defp detail_message(reply_to_message, photo) do
    [
      detail_line("Message URL", Map.get(photo, "source_message_url")),
      detail_line("Original URL", Map.get(photo, "url")),
      detail_line("Saved at", saved_at(photo, reply_to_message))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp detail_line(_label, nil), do: nil
  defp detail_line(_label, ""), do: nil
  defp detail_line(label, value), do: "#{label}: #{value}"

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
