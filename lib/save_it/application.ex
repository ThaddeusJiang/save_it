defmodule SaveIt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    token = Application.fetch_env!(:save_it, :telegram_bot_token)

    children = [
      ExGram,
      {SaveIt.Bot, [method: :polling, token: token]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SaveIt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
