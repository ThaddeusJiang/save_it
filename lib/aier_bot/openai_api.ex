defmodule AierBot.OpenaiApi do
  alias OpenaiEx.Image

  def openai() do
    api_key = Application.fetch_env!(:aier_bot, :openai_api_key)
    openai = OpenaiEx.new(api_key)

    openai
  end

  def image_generation(prompt) do
    openai = openai()

    fetch_blob = fn url ->
      Finch.build(:get, url)
      |> Finch.request!(OpenaiEx.Finch)
      |> Map.get(:body)
    end

    images =
      openai
      |> Image.create(%{
        prompt: prompt,
        n: 2,
        size: "1024x1024"
      })
      |> Map.get("data")
      |> Enum.map(fn x -> x["url"] |> fetch_blob.() end)

    {:ok, %{data: images}}
  end
end
