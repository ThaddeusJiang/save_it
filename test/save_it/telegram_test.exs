defmodule SaveIt.TelegramTest do
  use ExUnit.Case, async: false

  alias SaveIt.Telegram

  setup do
    previous_ex_gram = Application.get_all_env(:ex_gram)
    previous_save_it = Application.get_all_env(:save_it)

    Application.put_env(:ex_gram, :adapter, __MODULE__.Adapter)
    Application.put_env(:ex_gram, :token, "test-token")
    Application.put_env(:save_it, :telegram_rate_limit_delay_ms, 0)
    Application.put_env(:save_it, :test_pid, self())

    on_exit(fn ->
      restore_env(:ex_gram, previous_ex_gram)
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "returns structured rate limit errors when requested" do
    assert {:error, {:telegram_rate_limited, 37}} =
             Telegram.send_message(12_345, "rate-limited", on_rate_limit: :return)

    assert_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: 12_345, text: "rate-limited"}}
  end

  test "schedules one progress retry and deletes the source message after success" do
    parent = self()
    chat = %{id: 12_345}
    source_message = %{message_id: 109}

    assert :error =
             Telegram.handle_progress_rate_limit(chat, source_message, 37, 0, fn retry_attempt ->
               send(parent, {:retry, retry_attempt})
               :ok
             end)

    assert_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: 12_345, text: retry_notice}}

    assert retry_notice =~ "Telegram is rate limiting me."
    assert retry_notice =~ "Next automatic retry"
    assert retry_notice =~ "in 37 seconds"
    assert retry_notice =~ "only retry automatically once"

    assert_receive {:retry, 1}

    assert_receive {:exgram_request, :post, "/bottest-token/deleteMessage",
                    %{chat_id: 12_345, message_id: 109}}
  end

  defmodule Adapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(Application.fetch_env!(:save_it, :test_pid), {:exgram_request, verb, path, body})

      case {verb, path, body} do
        {:post, "/bottest-token/sendMessage", %{text: "rate-limited"}} ->
          {:error,
           %ExGram.Error{
             code: 429,
             message: "Too Many Requests: retry after 37",
             metadata: %{parameters: %{retry_after: 37}}
           }}

        {:post, "/bottest-token/sendMessage", %{chat_id: chat_id}} ->
          {:ok, %{message_id: 73, chat: %{id: chat_id}}}

        {:post, "/bottest-token/deleteMessage", _body} ->
          {:ok, true}

        _ ->
          {:error, %ExGram.Error{code: 404}}
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
