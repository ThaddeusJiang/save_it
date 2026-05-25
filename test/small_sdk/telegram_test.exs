defmodule SmallSdk.TelegramTest do
  use ExUnit.Case, async: false

  alias SmallSdk.Telegram

  defmodule TestAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      send(Application.fetch_env!(:save_it, :test_pid), {:telegram_request, env})
      {:ok, %Tesla.Env{env | status: 200, body: %{"ok" => true, "result" => []}}}
    end
  end

  setup do
    previous_token = Application.get_env(:save_it, :telegram_bot_token)
    previous_test_pid = Application.get_env(:save_it, :test_pid)
    previous_adapter = Application.get_env(:tesla, SmallSdk.Telegram)

    Application.put_env(:save_it, :telegram_bot_token, "test-token")
    Application.put_env(:save_it, :test_pid, self())
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: TestAdapter)

    on_exit(fn ->
      restore_env(:save_it, :telegram_bot_token, previous_token)
      restore_env(:save_it, :test_pid, previous_test_pid)
      restore_env(:tesla, SmallSdk.Telegram, previous_adapter)
    end)

    :ok
  end

  test "send_media_group accepts files with source urls" do
    assert {:ok, []} =
             Telegram.send_media_group(123, [
               {"photo.jpg", {:file_content, <<1, 2, 3>>, "photo.jpg"}, "https://x.com/example"}
             ])

    assert_receive {:telegram_request, env}
    assert env.url == "https://api.telegram.org/bottest-token/sendMediaGroup"

    multipart = env.body
    assert %Tesla.Multipart{} = multipart

    assert multipart_field(multipart, "chat_id") == "123"

    assert multipart_file_part(multipart, "media0").body == <<1, 2, 3>>
    assert multipart_file_part(multipart, "media0").dispositions[:filename] == "photo.jpg"

    media =
      multipart
      |> multipart_field("media")
      |> Jason.decode!()

    assert media == [%{"type" => "photo", "media" => "attach://media0"}]
  end

  defp multipart_field(multipart, name) do
    multipart
    |> multipart_part(name)
    |> Map.fetch!(:body)
  end

  defp multipart_file_part(multipart, name) do
    multipart_part(multipart, name)
  end

  defp multipart_part(multipart, name) do
    Enum.find(multipart.parts, fn part -> part.dispositions[:name] == name end)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
