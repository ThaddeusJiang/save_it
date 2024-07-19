defmodule AierBot.Bot do
  alias AierBot.CobaltClient
  alias AierBot.AierApi
  alias AierBot.OpenaiApi

  @bot :aier_bot

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

  def handle({:command, :image, message}, context) do
    %{text: prompt, chat: %{id: chat_id}} = message

    case OpenaiApi.image_generation(prompt) do
      {:ok, response} -> image_generation_success(response, chat_id)
      {:error, error} -> answer(context, "Error: #{inspect(error)}")
    end
  end

  def handle({:text, text, _msg}, context) do
    # TODO: repeat
    # request download API
    data = CobaltClient.json(text)

    IO.inspect(data)

    answer(context, "#{data}")
    # case AierApi.create_memo(text) do
    #   {:ok, response} -> create_memo_success(response, context)
    #   {:error, error} -> answer(context, "Error: #{inspect(error)}")
    # end
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
