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

  def handle({:text, text, %{chat: chat}}, _context) do
    url = CobaltClient.get_download_url(text)
    {file_name, file_content} = FileDownloader.download(url)

    {:ok, _} = bot_send_file(chat.id, file_name, file_content)
  end

  defp bot_send_file(chat_id, file_name, file_content) do
    IO.inspect(file_name)

    cond do
      String.ends_with?(file_name, ".png") ->
        ExGram.send_photo(chat_id, {:file_content, file_content, file_name})

      String.ends_with?(file_name, ".jpg") ->
        ExGram.send_photo(chat_id, {:file_content, file_content, file_name})

      String.ends_with?(file_name, ".jpeg") ->
        ExGram.send_photo(chat_id, {:file_content, file_content, file_name})

      String.ends_with?(file_name, ".mp4") ->
        # {:file_content, iodata() | Enum.t(), String.t()}
        # MEMO: 注意：参数是 {:file_content, file_content, file_name} ，3 个元素的 tuple
        ExGram.send_video(chat_id, {:file_content, file_content, file_name})

      true ->
        ExGram.send_document(chat_id, {:file_content, file_content, file_name})
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
