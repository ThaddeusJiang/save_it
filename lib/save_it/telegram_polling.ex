defmodule SaveIt.TelegramPolling do
  @moduledoc """
  ExGram polling worker that keeps Telegram's pending update queue intact on startup.
  """

  use GenServer

  require Logger

  @polling_timeout 100
  @default_opts [limit: 100, timeout: 50]

  def start_link(%{bot: bot, token: token} = opts) do
    opts = Map.drop(opts, [:bot, :token])
    GenServer.start_link(__MODULE__, {:ok, bot, token, opts})
  end

  @impl GenServer
  def init({:ok, bot, token, opts}) do
    Process.flag(:trap_exit, true)
    start_time = ExGram.Telemetry.start([:updates, :init], %{bot: bot, method: :polling})
    opts = :ex_gram |> ExGram.Config.get(:polling, []) |> Keyword.merge(Keyword.new(opts))

    if Keyword.get(opts, :delete_webhook, true) do
      ExGram.delete_webhook(token: token)
    end

    Process.send_after(self(), {:fetch, :update_id}, @polling_timeout)
    ExGram.Telemetry.stop([:updates, :init], start_time, %{bot: bot, method: :polling})
    {:ok, {bot, token, nil, opts}}
  end

  @impl GenServer
  def terminate(_reason, {bot, _token, _uid, _opts}) do
    ExGram.Telemetry.emit([:updates, :shutdown], %{bot: bot, method: :polling})
  end

  @impl GenServer
  def handle_cast({:fetch, :update_id} = message, state), do: handle_info(message, state)

  @impl GenServer
  def handle_info(:timeout, state), do: handle_info({:fetch, :update_id}, state)

  @impl GenServer
  def handle_info({:fetch, :update_id}, {bot, token, uid, opts}) do
    start_meta = %{bot: bot}
    start_time = ExGram.Telemetry.start(:polling, start_meta)

    try do
      updates = get_updates(token, uid, opts)
      send_updates(updates, bot)

      next_uid = next_update_id(uid, updates)

      ExGram.Telemetry.stop(:polling, start_time, %{bot: bot, updates_count: length(updates)})

      {:noreply, {bot, token, next_uid, opts}, @polling_timeout}
    rescue
      error ->
        ExGram.Telemetry.exception(
          :polling,
          start_time,
          :error,
          error,
          __STACKTRACE__,
          start_meta
        )

        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        ExGram.Telemetry.exception(:polling, start_time, kind, reason, __STACKTRACE__, start_meta)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  def handle_info(unknown_message, state) do
    Logger.debug("Polling updates received an unknown message #{inspect(unknown_message)}")

    {:noreply, state, @polling_timeout}
  end

  defp get_updates(token, uid, opts) do
    opts = Keyword.take(opts, [:allowed_updates])

    opts =
      @default_opts
      |> Keyword.merge(opts)
      |> maybe_put_offset(uid)
      |> Keyword.put(:token, token)

    try do
      ExGram.get_updates!(opts)
    rescue
      error in ExGram.Error ->
        formatted_error = Exception.format(:error, error, __STACKTRACE__)
        Logger.error("[ExGram] Error fetching updates: #{formatted_error}")
        []
    end
  end

  defp maybe_put_offset(opts, nil), do: opts
  defp maybe_put_offset(opts, uid), do: Keyword.put(opts, :offset, uid)

  defp send_updates(updates, bot) do
    Enum.map(updates, &GenServer.call(bot, {:update, &1}))
  end

  defp next_update_id(actual, []), do: actual

  defp next_update_id(actual, updates) do
    updates
    |> Stream.map(&(&1.update_id + 1))
    |> Enum.reduce(actual, fn update_id, acc ->
      if is_nil(acc), do: update_id, else: max(update_id, acc)
    end)
  end
end
