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
  @telegram_file_too_large_reason "file is too large for Telegram Bot API upload."

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
  def handle({:message, %{chat: chat, caption: nil, photo: photos}}, _ctx) do
    photo = List.last(photos)

    file = ExGram.get_file!(photo.file_id)
    photo_file_content = Telegram.download_file_content!(file.file_path)

    chat_id = chat.id

    typesense_photo =
      safe_typesense_create_photo(%{
        image: Base.encode64(photo_file_content),
        caption: "",
        file_id: file.file_id,
        belongs_to_id: chat_id
      })

    case typesense_photo do
      nil ->
        :ok

      _ ->
        photos =
          safe_typesense_search_similar_photos(
            typesense_photo["id"],
            distance_threshold: 0.1,
            belongs_to_id: chat_id
          )

        answer_similar_photos_if_any(chat.id, photos)
    end
  end

  # caption: contains /similar or /search -> search similar photos; otherwise, find same photos
  def handle({:message, %{chat: chat, caption: caption, photo: photos}}, _ctx) do
    photo = List.last(photos)

    file = ExGram.get_file!(photo.file_id)
    photo_file_content = Telegram.download_file_content!(file.file_path)

    chat_id = chat.id

    caption =
      if String.contains?(caption, ["/similar", "/search"]) do
        ""
      else
        caption
      end

    typesense_photo =
      safe_typesense_create_photo(%{
        image: Base.encode64(photo_file_content),
        caption: caption,
        file_id: file.file_id,
        belongs_to_id: chat_id
      })

    case typesense_photo do
      nil ->
        :ok

      _ ->
        case caption do
          "" ->
            photos =
              safe_typesense_search_similar_photos(
                typesense_photo["id"],
                distance_threshold: 0.4,
                belongs_to_id: chat_id
              )

            answer_similar_photos(chat.id, photos)

          _ ->
            photos =
              safe_typesense_search_similar_photos(
                typesense_photo["id"],
                distance_threshold: 0.1,
                belongs_to_id: chat_id
              )

            answer_similar_photos_if_any(chat.id, photos)
        end
    end
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
    case ExGram.send_photo(chat_id, photo["file_id"],
           caption: photo["caption"],
           show_caption_above_media: true
         ) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send photo: #{inspect(reason)}")
        send_message(chat_id, "Failed to send photos.")
    end
  end

  defp answer_photos(chat_id, similar_photos) do
    media =
      Enum.map(similar_photos, fn photo ->
        %ExGram.Model.InputMediaPhoto{
          type: "photo",
          media: photo["file_id"],
          caption: photo["caption"],
          show_caption_above_media: true
        }
      end)

    case ExGram.send_media_group(chat_id, media) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send media group: #{inspect(reason)}")
        send_message(chat_id, "Failed to send photos.")
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
        deliver_downloaded_file(context, file)

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

        case bot_send_filenames(context.chat_id, downloaded_files,
               source_url: context.original_url,
               report_too_large: false
             ) do
          :ok ->
            delete_message(context.chat_id, context.progress_message_id)
            :ok

          {:error, reason} ->
            update_delivery_progress_message(context, [delivery_error_message(reason)])
            :error
        end
    end
  end

  defp download_and_store_files(%DownloadContext{} = context, download_urls) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_files(download_urls) do
      {:ok, files} ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))
        deliver_downloaded_files(context, files)

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

        case bot_send_file(context.chat_id, downloaded_file, {:file, downloaded_file},
               source_url: context.original_url,
               download_url: context.download_url,
               report_too_large: false
             ) do
          :ok ->
            delete_message(context.chat_id, context.progress_message_id)
            :ok

          {:error, reason} ->
            update_delivery_progress_message(context, [delivery_error_message(reason)])
            :error
        end
    end
  end

  defp download_and_store_file(%DownloadContext{} = context) do
    update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..1))

    case WebDownloader.download_file(context.download_url) do
      {:ok, %DownloadedFile{} = file} ->
        update_message(context.chat_id, context.progress_message_id, Enum.slice(@progress, 0..2))
        deliver_downloaded_file(context, file)

      _ ->
        update_message(context.chat_id, context.progress_message_id, "💔 Failed downloading file.")
        :error
    end
  end

  defp cache_single_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    FileHelper.write_file(file.file_name, file.file_content, context.cache_url)
    :ok
  end

  defp deliver_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    telegram_task =
      Task.async(fn ->
        send_downloaded_file_to_telegram(context, file)
      end)

    google_drive_task =
      Task.async(fn ->
        send_downloaded_file_to_google_drive(context, file)
      end)

    telegram_result = Task.await(telegram_task, :infinity)

    if telegram_result == :ok do
      cache_single_download(context, file)
    end

    google_drive_result = Task.await(google_drive_task, :infinity)

    handle_delivery_results(context, telegram_result, google_drive_result)
  end

  defp deliver_downloaded_files(%DownloadContext{} = context, files) do
    telegram_task =
      Task.async(fn ->
        send_downloaded_files_to_telegram(context, files)
      end)

    google_drive_task =
      Task.async(fn ->
        send_downloaded_files_to_google_drive(context, files)
      end)

    telegram_result = Task.await(telegram_task, :infinity)

    if telegram_result == :ok do
      safe_delivery_result(fn ->
        FileHelper.write_folder(context.purge_url, files)
        :ok
      end)
    end

    google_drive_result = Task.await(google_drive_task, :infinity)

    handle_delivery_results(context, telegram_result, google_drive_result)
  end

  defp send_downloaded_file_to_telegram(%DownloadContext{} = context, %DownloadedFile{} = file) do
    safe_delivery_result(fn ->
      bot_send_downloaded_file(context.chat_id, file,
        source_url: context.original_url,
        report_too_large: false
      )
    end)
  end

  defp send_downloaded_files_to_telegram(%DownloadContext{} = context, files) do
    safe_delivery_result(fn ->
      bot_send_files(context.chat_id, files,
        source_url: context.original_url,
        report_too_large: false
      )
    end)
  end

  defp send_downloaded_file_to_google_drive(
         %DownloadContext{} = context,
         %DownloadedFile{} = file
       ) do
    safe_delivery_result(fn ->
      upload_file_to_google_drive(context.chat_id, file)
    end)
  end

  defp send_downloaded_files_to_google_drive(%DownloadContext{} = context, files) do
    safe_delivery_result(fn ->
      upload_files_to_google_drive(context.chat_id, files)
    end)
  end

  defp safe_delivery_result(delivery_fun) do
    delivery_fun.()
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp handle_delivery_results(%DownloadContext{} = context, telegram_result, google_drive_result) do
    error_messages =
      [telegram_result, google_drive_result]
      |> Enum.map(&delivery_error_message/1)
      |> Enum.reject(&is_nil/1)

    if error_messages == [] do
      delete_message(context.chat_id, context.progress_message_id)
    else
      update_delivery_progress_message(context, error_messages)
    end

    case telegram_result do
      :ok -> :ok
      {:error, _reason} -> :error
    end
  end

  defp update_delivery_progress_message(%DownloadContext{} = context, error_messages) do
    update_message(
      context.chat_id,
      context.progress_message_id,
      Enum.slice(@progress, 0..2) ++ error_messages
    )
  end

  defp delivery_error_message(:ok), do: nil

  defp delivery_error_message(:telegram_file_too_large),
    do: telegram_error_message(@telegram_file_too_large_reason)

  defp delivery_error_message({:error, {:google_drive_upload_failed, reason}}),
    do: google_drive_error_message(reason)

  defp delivery_error_message({:error, :telegram_file_too_large}),
    do: telegram_error_message(@telegram_file_too_large_reason)

  defp delivery_error_message({:error, reason}), do: telegram_error_message(reason)

  defp telegram_error_message(reason),
    do: "Send to telegram failed, #{format_error_reason(reason)}"

  defp google_drive_error_message(reason),
    do: "Send to google drive failed, #{format_error_reason(reason)}"

  defp format_error_reason(%{body: %{"error" => %{"message" => message}}})
       when is_binary(message),
       do: message

  defp format_error_reason(%{body: %{"message" => message}}) when is_binary(message), do: message

  defp format_error_reason(%{status: status, body: body}) do
    body_reason = format_error_reason(%{body: body})

    if body_reason == inspect(body) do
      "status #{status}, #{body_reason}"
    else
      body_reason
    end
  end

  defp format_error_reason(%{message: message}) when is_binary(message), do: message
  defp format_error_reason(%{body: body}), do: format_error_reason(body)

  defp format_error_reason(results) when is_list(results) do
    Enum.find_value(results, inspect(results), fn
      {:error, reason} -> format_error_reason(reason)
      _ -> nil
    end)
  end

  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp format_error_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_error_reason(reason), do: inspect(reason)

  defp upload_file_to_google_drive(chat_id, %DownloadedFile{} = file) do
    case GoogleDrive.upload_file_content(chat_id, file.file_content, file.file_name) do
      {:ok, _body} -> :ok
      {:error, :google_drive_not_logged_in} -> :ok
      {:error, reason} -> {:error, {:google_drive_upload_failed, reason}}
    end
  end

  defp upload_files_to_google_drive(chat_id, files) do
    case GoogleDrive.upload_files(chat_id, files) do
      {:ok, _results} -> :ok
      {:error, :google_drive_not_logged_in} -> :ok
      {:error, reason} -> {:error, {:google_drive_upload_failed, reason}}
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
    report_too_large = Keyword.get(opts, :report_too_large, true)

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
        bot_send_downloaded_file(chat_id, file,
          source_url: source_url,
          report_too_large: report_too_large
        )
      end)
    end
  end

  defp bot_send_downloaded_file(chat_id, %DownloadedFile{} = file, opts) do
    bot_send_file(
      chat_id,
      file.file_name,
      {:file_content, file.file_content, file.file_name},
      Keyword.put_new(opts, :download_url, file.download_url)
    )
  end

  defp bot_send_filenames(chat_id, filenames, opts) do
    source_url = Keyword.get(opts, :source_url)
    report_too_large = Keyword.get(opts, :report_too_large, true)

    if all_images?(filenames) and length(filenames) > 1 do
      bot_send_media_group(
        chat_id,
        Enum.map(filenames, fn filename -> {filename, {:file, filename}, source_url} end)
      )
    else
      Enum.each(filenames, fn filename ->
        bot_send_file(chat_id, filename, {:file, filename},
          source_url: source_url,
          report_too_large: report_too_large
        )
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
              download_url: download_url,
              report_too_large: false
            )

          {file_name, content, source_url} ->
            bot_send_file(chat_id, file_name, content,
              source_url: source_url,
              report_too_large: false
            )

          {file_name, content} ->
            bot_send_file(chat_id, file_name, content, report_too_large: false)
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
    report_too_large = Keyword.get(opts, :report_too_large, true)

    cond do
      telegram_upload_too_large?(content) ->
        if report_too_large do
          send_message(chat_id, @telegram_file_too_large_message)
        end

        {:error, :telegram_file_too_large}

      true ->
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
        with {:ok, msg} <-
               safe_send(fn -> ExGram.send_photo(chat_id, content, caption: caption) end) do
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
        end

      ".mp4" ->
        normalize_send_result(
          safe_send(fn ->
            ExGram.send_video(chat_id, content, supports_streaming: true, caption: caption)
          end)
        )

      ".gif" ->
        normalize_send_result(
          safe_send(fn -> ExGram.send_animation(chat_id, content, caption: caption) end)
        )

      _ ->
        normalize_send_result(
          safe_send(fn -> ExGram.send_document(chat_id, content, caption: caption) end)
        )
    end
  end

  defp safe_send(send_fun) do
    send_fun.()
  rescue
    error ->
      Logger.error("Failed to send file to Telegram: #{Exception.message(error)}")
      {:error, error}
  catch
    kind, reason ->
      Logger.error("Failed to send file to Telegram: #{inspect({kind, reason})}")
      {:error, reason}
  end

  defp normalize_send_result({:ok, _message}), do: :ok
  defp normalize_send_result({:error, reason}), do: {:error, reason}

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
    PhotoService.create_photo!(photo_params)
  rescue
    error ->
      Logger.error("Typesense create_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, reason ->
      Logger.error("Typesense create_photo failed: #{inspect({kind, reason})}")
      nil
  end

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
