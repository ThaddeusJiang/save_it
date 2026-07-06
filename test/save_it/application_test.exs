defmodule SaveIt.ApplicationTest do
  use ExUnit.Case, async: false

  setup do
    previous_token = Application.get_env(:save_it, :telegram_bot_token)
    previous_start_bot = Application.get_env(:save_it, :start_bot?)

    on_exit(fn ->
      restore_env(:save_it, :telegram_bot_token, previous_token)
      restore_env(:save_it, :start_bot?, previous_start_bot)
    end)
  end

  test "fails fast when Telegram bot token is missing" do
    Application.put_env(:save_it, :telegram_bot_token, nil)

    assert_raise RuntimeError, ~r/TELEGRAM_BOT_TOKEN must be set/, fn ->
      SaveIt.Application.start(:normal, [])
    end
  end

  test "fails fast when Telegram bot token is blank" do
    Application.put_env(:save_it, :telegram_bot_token, "  ")

    assert_raise RuntimeError, ~r/TELEGRAM_BOT_TOKEN must be set/, fn ->
      SaveIt.Application.start(:normal, [])
    end
  end

  test "uses polling that keeps pending Telegram updates on startup" do
    Application.put_env(:save_it, :telegram_bot_token, "test-token")
    Application.put_env(:save_it, :start_bot?, true)

    assert {SaveIt.Bot, [method: SaveIt.TelegramPolling, token: "test-token"]} in SaveIt.Application.children()
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
