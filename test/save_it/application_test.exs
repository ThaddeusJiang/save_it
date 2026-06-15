defmodule SaveIt.ApplicationTest do
  use ExUnit.Case, async: false

  setup do
    previous_token = Application.get_env(:save_it, :telegram_bot_token)

    on_exit(fn ->
      restore_env(:save_it, :telegram_bot_token, previous_token)
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

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
