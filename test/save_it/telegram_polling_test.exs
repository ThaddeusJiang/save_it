defmodule SaveIt.TelegramPollingTest do
  use ExUnit.Case, async: false

  alias SaveIt.TelegramPolling

  setup do
    previous_ex_gram = Application.get_all_env(:ex_gram)
    previous_save_it = Application.get_all_env(:save_it)

    Application.put_env(:ex_gram, :adapter, __MODULE__.Adapter)
    Application.put_env(:save_it, :test_pid, self())

    on_exit(fn ->
      restore_env(:ex_gram, previous_ex_gram)
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "initial fetch starts from the earliest unconfirmed update" do
    Application.put_env(:save_it, :polling_test_updates, [])

    {:ok, dispatcher} = GenServer.start_link(__MODULE__.Dispatcher, self())
    {:ok, polling} = TelegramPolling.start_link(%{bot: dispatcher, token: "test-token"})

    assert_receive {:telegram_request, :get, "/bottest-token/getUpdates", body}, 500
    refute Map.has_key?(body, :offset)
    assert body.limit == 100
    assert body.timeout == 50

    GenServer.stop(polling)
    GenServer.stop(dispatcher)
  end

  test "next fetch acknowledges processed updates" do
    Application.put_env(:save_it, :polling_test_updates, [
      %{update_id: 41, message: %{message_id: 1, chat: %{id: 123}}}
    ])

    {:ok, dispatcher} = GenServer.start_link(__MODULE__.Dispatcher, self())
    {:ok, polling} = TelegramPolling.start_link(%{bot: dispatcher, token: "test-token"})

    assert_receive {:telegram_request, :get, "/bottest-token/getUpdates", first_body}, 500
    refute Map.has_key?(first_body, :offset)
    assert_receive {:dispatched_update, 41}

    send(polling, {:fetch, :update_id})

    assert_receive {:telegram_request, :get, "/bottest-token/getUpdates", second_body}, 500
    assert second_body.offset == 42

    GenServer.stop(polling)
    GenServer.stop(dispatcher)
  end

  defmodule Dispatcher do
    use GenServer

    @impl GenServer
    def init(parent), do: {:ok, parent}

    @impl GenServer
    def handle_call({:update, update}, _from, parent) do
      send(parent, {:dispatched_update, update.update_id})
      {:reply, :ok, parent}
    end
  end

  defmodule Adapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(Application.fetch_env!(:save_it, :test_pid), {:telegram_request, verb, path, body})

      case {verb, path, body} do
        {:post, "/bottest-token/deleteWebhook", _body} ->
          {:ok, true}

        {:get, "/bottest-token/getUpdates", %{offset: 42}} ->
          {:ok, []}

        {:get, "/bottest-token/getUpdates", body} when not is_map_key(body, :offset) ->
          {:ok, Application.fetch_env!(:save_it, :polling_test_updates)}
      end
    end
  end

  defp restore_env(app, env) do
    app
    |> Application.get_all_env()
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(env, fn {key, value} -> Application.put_env(app, key, value) end)
  end
end
