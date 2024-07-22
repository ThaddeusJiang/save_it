defmodule AierBot.Bot do
  alias AierBot.CobaltClient
  alias AierBot.FileDownloader

  @bot :save_it_bot

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")
  command("help", description: "Print the bot's help")
  command("image", description: "Generate image from text")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot(), do: @bot

  def handle({:command, :start, _msg}, context) do
    answer(context, "Hi!")
  end

  def handle({:command, :help, _msg}, context) do
    answer(context, "Here is your help:")
  end

  # def handle({:text, text, message}, context) do
  def handle({:text, text, %{chat: chat}}, _context) do
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
          {:ok, file_name, file_content} = FileDownloader.download(download_url)

          {:ok, _} = bot_send_file(chat.id, file_name, file_content, url)

        {:error, error} ->
          ExGram.send_message(chat.id, "Failed to download file. Reason: #{inspect(error)}")
      end
    end
  end

  defp extract_urls_from_string(str) do
    regex = ~r/http[s]?:\/\/[^\s]+/
    matches = Regex.scan(regex, str)

    # 扁平化匹配结果，因为Regex.scan返回的是一个列表的列表
    Enum.map(matches, fn [url] -> url end)
  end

  # TODO: 额外参数可以使用 options 来传递
  defp bot_send_file(chat_id, file_name, file_content, _original_url) do
    IO.inspect(file_name)

    cond do
      String.ends_with?(file_name, ".png") ->
        ExGram.send_photo(
          chat_id,
          {:file_content, file_content, file_name}
          # TODO: original_url 作为 caption 收益不高，AI generated searchable caption 会更好
          # original_text
          # AI generated searchable caption
          # and some other metadata
          # caption: "Image from URL: #{original_url}"
        )

      String.ends_with?(file_name, ".jpg") ->
        ExGram.send_photo(
          chat_id,
          {:file_content, file_content, file_name}
          # caption: "Image from URL: #{original_url}"
        )

      String.ends_with?(file_name, ".jpeg") ->
        ExGram.send_photo(
          chat_id,
          {:file_content, file_content, file_name}
          # caption: "Image from URL: #{original_url}"
        )

      String.ends_with?(file_name, ".mp4") ->
        # {:file_content, iodata() | Enum.t(), String.t()}
        # MEMO: 注意：参数是 {:file_content, file_content, file_name} ，3 个元素的 tuple
        ExGram.send_video(
          chat_id,
          {:file_content, file_content, file_name}
          # caption: "Image from URL: #{original_url}"
        )

      true ->
        ExGram.send_document(
          chat_id,
          {:file_content, file_content, file_name}
          # caption: "Image from URL: #{original_url}"
        )
    end
  end

  def create_memo_success(_, context) do
    answer(context, "Memo saved!")
  end

  def image_generation_success(%{data: images}, chat_id) do
    [first | _] = images

    res = ExGram.send_photo(chat_id, {:file_content, first, "image.png"}, bot: @bot)

    IO.inspect(res)
  end
end
