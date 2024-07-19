defmodule AierBot.AierApi do
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://www.aier.app")
  plug(Tesla.Middleware.JSON)

  def aier_api_token do
    Application.fetch_env!(:aier_bot, :aier_api_token)
  end

  def create_memo(memo) do
    url = Path.join("/api/webhooks/memoCreate", aier_api_token())

    body = %{
      content: memo,
      created_at: DateTime.to_iso8601(DateTime.utc_now()),
      # TODO: real source_url
      source_url: "telegram bot"
    }

    post(url, body)
  end
end
