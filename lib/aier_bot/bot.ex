defmodule AierBot.Bot do
  require Logger
  alias AierBot.CobaltClient
  alias AierBot.FileHelper

  @bot :save_it_bot

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")
  command("help", description: "Print the bot's help")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot(), do: @bot

  def handle({:command, :start, _msg}, context) do
    answer(context, "Hi! I'm a bot that can download images and videos, just give me a link.")
  end

  def handle({:command, :help, _msg}, context) do
    answer(context, "Here is your help:")
  end

  # def handle({:text, text, message}, context) do
  def handle({:text, text, %{chat: chat, message_id: message_id}}, _context) do
    urls = extract_urls_from_string(text)

    if Enum.empty?(urls) do
      # TODO: 思考：使用 DSL answer 还是 function send_message?
      # answer(context, "No URL found.")
      ExGram.send_message(chat.id, "No URL found.")
    else
      # MEMO: for payment, free only one url, for multiple urls, need to pay
      url = List.first(urls)

      case CobaltClient.get_download_url(url) do
        {:ok, download_url} ->
          case FileHelper.get_downloaded_file(download_url) do
            nil ->
              case FileHelper.download(download_url) do
                {:ok, file_name, file_content} ->
                  {:ok, _} =
                    bot_send_file(chat.id, file_name, {:file_content, file_content, file_name},
                      original_url: url
                    )

                  delete_message(chat.id, message_id)
                  FileHelper.write_file(file_name, file_content, download_url)

                {:error, error} ->
                  ExGram.send_message(chat.id, "Failed to download file. #{inspect(error)}")
              end

            download_file ->
              Logger.info("File already downloaded, don't need to download again")

              {:ok, _} =
                bot_send_file(chat.id, download_file, {:file, download_file}, original_url: url)

              delete_message(chat.id, message_id)
          end

        {:error, error} ->
          ExGram.send_message(chat.id, error)
      end
    end
  end

  defp extract_urls_from_string(str) do
    regex = ~r/http[s]?:\/\/[^\s]+/
    matches = Regex.scan(regex, str)

    # 扁平化匹配结果，因为Regex.scan返回的是一个列表的列表
    Enum.map(matches, fn [url] -> url end)
  end

  defp delete_message(chat_id, message_id) do
    ExGram.delete_message(chat_id, message_id)
  end

  defp bot_send_file(chat_id, file_name, file_content, options) do
    content =
      case file_content do
        {:file, file} -> {:file, file}
        {:file_content, file_content, file_name} -> {:file_content, file_content, file_name}
      end

    caption = options[:original_url]

    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        ExGram.send_photo(chat_id, content, caption: caption)

      ".mp4" ->
        ExGram.send_video(chat_id, content, caption: caption, supports_streaming: true)

      ".gif" ->
        ExGram.send_animation(chat_id, content, caption: caption)

      _ ->
        ExGram.send_document(chat_id, content, caption: caption)
    end
  end

  defp file_extension(file_name) do
    Path.extname(file_name)
  end
end
