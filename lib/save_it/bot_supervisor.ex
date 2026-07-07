defmodule SaveIt.BotSupervisor do
  @moduledoc false

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {enabled?, supervisor_opts} = Keyword.pop(opts, :enabled?, telegram_bot_enabled?())

    if enabled? do
      supervisor_opts = Keyword.put_new(supervisor_opts, :name, __MODULE__)

      Supervisor.start_link(__MODULE__, [token: telegram_bot_token!()], supervisor_opts)
    else
      :ignore
    end
  end

  @impl true
  def init(opts) do
    opts
    |> Keyword.fetch!(:token)
    |> child_specs()
    |> Supervisor.init(strategy: :one_for_one)
  end

  @doc false
  def child_specs(token) do
    [
      ExGram,
      {SaveIt.Bot, [method: SaveIt.TelegramPolling, token: token]}
    ]
  end

  defp telegram_bot_enabled? do
    Application.get_env(:save_it, :telegram_bot_enabled?, true)
  end

  defp telegram_bot_token! do
    case Application.fetch_env(:save_it, :telegram_bot_token) do
      {:ok, token} when is_binary(token) ->
        require_telegram_bot_token!(token)

      _ ->
        raise "TELEGRAM_BOT_TOKEN must be set"
    end
  end

  defp require_telegram_bot_token!(token) do
    if String.trim(token) == "" do
      raise "TELEGRAM_BOT_TOKEN must be set"
    end

    token
  end
end
