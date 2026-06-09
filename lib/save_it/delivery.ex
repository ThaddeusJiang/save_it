defmodule SaveIt.Delivery do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @name)
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def deliver(telegram_fun, google_drive_fun, after_telegram_success_fun) do
    GenServer.call(
      @name,
      {:deliver, telegram_fun, google_drive_fun, after_telegram_success_fun},
      :infinity
    )
  end

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call(
        {:deliver, telegram_fun, google_drive_fun, after_telegram_success_fun},
        from,
        state
      ) do
    Task.start(fn ->
      telegram_task = Task.async(fn -> safe_call(telegram_fun) end)
      google_drive_task = Task.async(fn -> safe_call(google_drive_fun) end)

      telegram_result = Task.await(telegram_task, :infinity)

      if telegram_result == :ok do
        safe_call(after_telegram_success_fun)
      end

      google_drive_result = Task.await(google_drive_task, :infinity)

      GenServer.reply(from, {telegram_result, google_drive_result})
    end)

    {:noreply, state}
  end

  defp safe_call(fun) do
    fun.()
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end
end
