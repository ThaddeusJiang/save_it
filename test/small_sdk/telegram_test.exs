defmodule SmallSdk.TelegramTest do
  use ExUnit.Case, async: false

  alias SmallSdk.Telegram

  setup do
    previous_token = Application.get_env(:save_it, :telegram_bot_token)
    previous_test_pid = Application.get_env(:save_it, :test_pid)
    previous_req_options = Application.get_env(:save_it, :telegram_req_options)

    Application.put_env(:save_it, :telegram_bot_token, "test-token")
    Application.put_env(:save_it, :test_pid, self())
    Application.put_env(:save_it, :telegram_req_options, adapter: &__MODULE__.request_adapter/1)

    on_exit(fn ->
      restore_env(:save_it, :telegram_bot_token, previous_token)
      restore_env(:save_it, :test_pid, previous_test_pid)
      restore_env(:save_it, :telegram_req_options, previous_req_options)
    end)

    :ok
  end

  test "send_media_group accepts files with source urls and captions every media item" do
    assert {:ok, []} =
             Telegram.send_media_group(
               123,
               [
                 {"photo.jpg", {:file_content, <<1, 2, 3>>, "photo.jpg"}, "https://x.com/example"}
               ],
               caption: "created at 2024-06-01"
             )

    assert_receive {:telegram_request, env}
    assert URI.to_string(env.url) == "https://api.telegram.org/bottest-token/sendMediaGroup"

    multipart = IO.iodata_to_binary(env.body)

    assert multipart =~ ~s(name="chat_id")
    assert multipart =~ "123"

    assert multipart =~ ~s(name="media0"; filename="photo.jpg")
    assert multipart =~ <<1, 2, 3>>
    assert multipart =~ ~s(name="media")
    assert multipart =~ ~s("type":"photo")
    assert multipart =~ ~s("media":"attach://media0")
    assert multipart =~ ~s("caption":"created at 2024-06-01")
  end

  def request_adapter(request) do
    send(Application.fetch_env!(:save_it, :test_pid), {:telegram_request, request})

    {request,
     %Req.Response{
       status: 200,
       body: %{"ok" => true, "result" => []}
     }}
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
