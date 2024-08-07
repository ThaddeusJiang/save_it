defmodule AierBot.Bot do
  require Logger
  alias AierBot.CobaltClient
  alias AierBot.FileHelper
  alias AierBot.GoogleDrive
  alias AierBot.GoogleOAuth2DeviceFlow

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
  command("about", description: "About the bot")
  command("code", description: "Get Device Code for Google Drive")
  command("login", description: "Login to Google Drive")
  command("folder", description: "Set Google Drive Folder")

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

  def handle({:command, :login, %{chat: chat}}, _context) do
    device_code = FileHelper.get_google_device_code(chat.id)
    # %{
    #   "google_device_code" => device_code
    # } = SettingsStore.get(msg.chat.id)

    case GoogleOAuth2DeviceFlow.exchange_device_code_for_token(device_code) do
      {:ok, body} ->
        IO.inspect(body, label: "body")
        # SettingsStore.update_google_oauth(msg.chat.id, body)
        FileHelper.set_google_access_token(chat.id, body["access_token"])
        send_message(chat.id, "Login successful")

      {:error, error} ->
        Logger.error("Login failed: #{inspect(error)}")
        send_message(chat.id, "Login failed")
    end
  end

  # def handle({:command, :files, %{chat: chat}}, _context) do
  #   case GoogleDrive.list_files(chat.id) do
  #     {:ok, files} ->
  #       send_message(chat.id, """
  #       Files:
  #       #{Enum.map(files, fn file -> file["name"] end) |> Enum.join("\n")}
  #       """)

  #     {:error, error} ->
  #       IO.inspect(error)
  #   end
  # end

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

  # def handle({:text, text, message}, context) do
  def handle({:text, text, %{chat: chat, message_id: message_id}}, _context) do
    urls = extract_urls_from_string(text)

    unless Enum.empty?(urls) do
      {:ok, progress_message} = send_message(chat.id, Enum.at(@progress, 0))
      # TODO: for payment, free only one url, for multiple urls, need to pay
      url = List.first(urls)

      case CobaltClient.get_download_url(url) do
        {:ok, url, download_urls} ->
          case FileHelper.get_downloaded_files(download_urls) do
            nil ->
              update_message(chat.id, progress_message.message_id, Enum.slice(@progress, 0..1))
              # TODO:
              case FileHelper.download_files(download_urls) do
                {:ok, files} ->
                  update_message(
                    chat.id,
                    progress_message.message_id,
                    Enum.slice(@progress, 0..2)
                  )

                  # TODO:
                  # bot_send_media_group(chat.id, files)
                  bot_send_files(chat.id, files)

                  delete_messages(chat.id, [message_id, progress_message.message_id])
                  # TODO: Google Drive Uploader
                  FileHelper.write_folder(url, files)

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

              # TODO:
              # bot_send_media_group(chat.id, downloaded_files)
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

                  GoogleDrive.upload_file_content(chat.id, file_content, file_name)
                  FileHelper.write_file(file_name, file_content, download_url)
                  delete_messages(chat.id, [message_id, progress_message.message_id])

                _ ->
                  update_message(
                    chat.id,
                    progress_message.message_id,
                    "💔 Failed downloading file."
                  )
              end

            download_file ->
              Logger.info("👍 File already downloaded, don't need to download again")

              update_message(chat.id, progress_message.message_id, Enum.slice(@progress, 0..2))

              bot_send_file(chat.id, download_file, {:file, download_file})
              GoogleDrive.upload_file(chat.id, download_file)
              delete_messages(chat.id, [message_id, progress_message.message_id])
          end

        {:error, msg} ->
          update_message(chat.id, progress_message.message_id, msg)
      end
    end
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
        ExGram.send_photo(chat_id, content)

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
end
