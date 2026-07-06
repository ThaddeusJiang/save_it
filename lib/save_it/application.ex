defmodule SaveIt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :logger.add_handler(:my_sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SaveIt.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  @doc false
  def children do
    token = Application.fetch_env!(:save_it, :telegram_bot_token) |> require_telegram_bot_token!()

    if Application.get_env(:save_it, :start_bot?, true) do
      [
        ExGram,
        {SaveIt.Bot, [method: SaveIt.TelegramPolling, token: token]}
      ]
    else
      []
    end
  end

  defp require_telegram_bot_token!(token) when is_binary(token) do
    if String.trim(token) == "" do
      raise "TELEGRAM_BOT_TOKEN must be set"
    end

    token
  end

  defp require_telegram_bot_token!(_token) do
    raise "TELEGRAM_BOT_TOKEN must be set"
  end
end
