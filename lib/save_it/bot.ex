defmodule SaveIt.Bot do
  require Logger
  alias SaveIt.CobaltClient
  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive
  alias SaveIt.GoogleOAuth2DeviceFlow

  alias SaveIt.TypesenseClient

  alias SmallSdk.Telegram

  @bot :save_it_bot

  @progress [
    "Searching 🔎",
    "Downloading 💦",
    "Uploading 💭",
    "Have fun! 🎉"
  ]

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")
  command("search", description: "Search similar photos by photo")
  command("login", description: "Login")
  command("code", description: "Get code for login")
  command("folder", description: "Update Google Drive folder ID")
  command("about", description: "About the bot")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot(), do: @bot

  def handle({:command, :start, _msg}, context) do
    answer(context, "Hi! I'm a bot that can download images and videos, just give me a link.")
  end

  def handle({:command, :about, _msg}, context) do
    answer(context, """
    This bot is created by @ThaddeusJiang, feel free to contact me if you have any questions.

    GitHub: https://github.com/ThaddeusJiang
    Blog: https://thaddeusjiang.com
    X: https://x.com/thaddeusjiang
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
          # TODO: 可以继续提取到一个函数中
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

  def handle({:command, :search, %{chat: chat, photo: nil}}, _context) do
    send_message(chat.id, "Please send me a photo to search.")
    # TODO: ex_gram 是否可以支持连续对话？
  end

  def handle({:message, %{chat: chat, caption: caption, photo: photos}}, ctx) do
    photo = List.last(photos)

    bot_id = ctx.bot_info.id

    similar_photos =
      search_similar_photos_based_on_caption(bot_id, photo, caption)

    answer_similar_photos(chat.id, similar_photos)
  end

  def handle({:text, text, %{chat: chat, message_id: message_id}}, _context) do
    urls = extract_urls_from_string(text)

    unless Enum.empty?(urls) do
      {:ok, progress_message} = send_message(chat.id, Enum.at(@progress, 0))
      url = List.first(urls)

      case CobaltClient.get_download_url(url) do
        {:ok, url, download_urls} ->
          case FileHelper.get_downloaded_files(download_urls) do
            nil ->
              update_message(chat.id, progress_message.message_id, Enum.slice(@progress, 0..1))

              case FileHelper.download_files(download_urls) do
                {:ok, files} ->
                  update_message(
                    chat.id,
                    progress_message.message_id,
                    Enum.slice(@progress, 0..2)
                  )

                  # TODO: send media group
                  # bot_send_media_group(chat.id, files)
                  bot_send_files(chat.id, files)

                  delete_messages(chat.id, [message_id, progress_message.message_id])
                  FileHelper.write_folder(url, files)
                  # TODO: 给图片添加 emoji
                  GoogleDrive.upload_files(chat.id, files)

                _ ->
                  update_message(
                    chat.id,
                    progress_message.message_id,
                    "💔 Failed downloading file."
                  )
              end

            downloaded_files ->
              Logger.info("👍 File already downloaded, don't need to download again")

              update_message(chat.id, progress_message.message_id, Enum.slice(@progress, 0..2))

              # TODO: bot_send_media_group(chat.id, downloaded_files)
              bot_send_filenames(chat.id, downloaded_files)
              delete_messages(chat.id, [message_id, progress_message.message_id])
          end

        {:ok, download_url} ->
          case FileHelper.get_downloaded_file(download_url) do
            nil ->
              update_message(chat.id, progress_message.message_id, Enum.slice(@progress, 0..1))

              case FileHelper.download(download_url) do
                {:ok, file_name, file_content} ->
                  update_message(
                    chat.id,
                    progress_message.message_id,
                    Enum.slice(@progress, 0..2)
                  )

                  bot_send_file(chat.id, file_name, {:file_content, file_content, file_name})

                  delete_messages(chat.id, [message_id, progress_message.message_id])
                  FileHelper.write_file(file_name, file_content, download_url)
                  GoogleDrive.upload_file_content(chat.id, file_content, file_name)

                _ ->
                  update_message(
                    chat.id,
                    progress_message.message_id,
                    "💔 Failed downloading file."
                  )
              end

            downloaded_file ->
              Logger.info("👍 File already downloaded, don't need to download again")

              update_message(chat.id, progress_message.message_id, Enum.slice(@progress, 0..2))

              bot_send_file(chat.id, downloaded_file, {:file, downloaded_file})
              delete_messages(chat.id, [message_id, progress_message.message_id])
          end

        {:error, msg} ->
          update_message(chat.id, progress_message.message_id, msg)
      end
    end
  end

  def handle(
        {:update,
         %ExGram.Model.Update{message: nil, edited_message: nil, channel_post: _channel_post}},
        _context
      ) do
    Logger.warning("this is a channel post, ignore it")
    {:ok, nil}
  end

  # def handle({:update, update}, _context) do
  #   Logger.debug(":update: #{inspect(update)}")
  #   {:ok, nil}
  # end

  # Doc: https://hexdocs.pm/ex_gram/readme.html#how-to-handle-messages
  # def handle({:message, message}, _context) do
  #   Logger.debug(":message: #{inspect(message)}")
  #   {:ok, nil}
  # end

  defp search_similar_photos(bot_id, photo, distance_threshold) do
    file = ExGram.get_file!(photo.file_id)

    photo_file_content = Telegram.download_file_content!(file.file_path)

    TypesenseClient.search_photos!(
      %{
        url: photo_url(bot_id, file.file_id),
        caption: Map.get(photo, "caption", ""),
        image: Base.encode64(photo_file_content)
      },
      distance_threshold: distance_threshold
    )
  end

  defp pick_file_id_from_photo_url(photo_url) do
    %{"file_id" => file_id} =
      Regex.named_captures(~r"/files/(?<bot_id>\d+)/(?<file_id>.+)", photo_url)

    file_id
  end

  defp answer_similar_photos(chat_id, nil) do
    send_message(chat_id, "No similar photos found.")
  end

  defp answer_similar_photos(chat_id, similar_photos) do
    media =
      Enum.map(similar_photos, fn photo ->
        %ExGram.Model.InputMediaPhoto{
          type: "photo",
          media: pick_file_id_from_photo_url(photo["url"])
        }
      end)

    ExGram.send_media_group(chat_id, media)
  end

  defp extract_urls_from_string(str) do
    regex = ~r/http[s]?:\/\/[^\s]+/
    matches = Regex.scan(regex, str)

    # 扁平化匹配结果，因为Regex.scan返回的是一个列表的列表
    Enum.map(matches, fn [url] -> url end)
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

  defp delete_messages(chat_id, message_ids) do
    Enum.each(message_ids, fn message_id -> delete_message(chat_id, message_id) end)
  end

  # defp bot_send_media_group(chat_id, files) do
  #   media =
  #     Enum.map(files, fn {file_name, file_content} ->
  #       %ExGram.Model.InputMediaDocument{
  #         type: "document",
  #         media: file_content
  #       }
  #     end)

  #   ExGram.send_media_group(chat_id, media)
  # end

  defp bot_send_files(chat_id, files) do
    Enum.each(files, fn {file_name, file_content} ->
      bot_send_file(chat_id, file_name, {:file_content, file_content, file_name})
    end)
  end

  defp bot_send_filenames(chat_id, filenames) do
    Enum.each(filenames, fn filename -> bot_send_file(chat_id, filename, {:file, filename}) end)
  end

  defp bot_send_file(chat_id, file_name, file_content, _opts \\ []) do
    content =
      case file_content do
        {:file, file} -> {:file, file}
        {:file_content, file_content, file_name} -> {:file_content, file_content, file_name}
      end

    # caption = opts[:caption]

    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        {:ok, msg} = ExGram.send_photo(chat_id, content)
        bot_id = msg.from.id
        file_id = get_file_id(msg)

        image_base64 =
          case file_content do
            {:file, file} -> File.read!(file) |> Base.encode64()
            {:file_content, file_content, _file_name} -> Base.encode64(file_content)
          end

        TypesenseClient.create_photo!(%{
          url: photo_url(bot_id, file_id),
          caption: file_name,
          image: image_base64
        })

      ".mp4" ->
        ExGram.send_video(chat_id, content, supports_streaming: true)

      ".gif" ->
        ExGram.send_animation(chat_id, content)

      _ ->
        ExGram.send_document(chat_id, content)
    end
  end

  defp file_extension(file_name) do
    Path.extname(file_name)
  end

  defp get_file_id(msg) do
    photo =
      msg.photo
      |> List.last()

    photo.file_id
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

  defp photo_url(bot_id, file_id) do
    proxy_url = Application.fetch_env!(:save_it, :web_url) <> "/telegram/files"
    Logger.debug("bot_id: #{bot_id}, file_id: #{file_id}, proxy_url: #{proxy_url}")

    "#{proxy_url}/#{bot_id}/#{file_id}"
  end

  defp search_similar_photos_based_on_caption(bot_id, photo, caption) do
    if caption && String.contains?(caption, "/search") do
      search_similar_photos(bot_id, photo, 0.5)
    else
      search_similar_photos(bot_id, photo, 0.1)
    end
  end
end
