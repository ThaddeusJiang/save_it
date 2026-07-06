defmodule SaveIt.BotSupervisorTest do
  use ExUnit.Case, async: false

  setup do
    previous_token = Application.get_env(:save_it, :telegram_bot_token)
    previous_telegram_bot_enabled? = Application.get_env(:save_it, :telegram_bot_enabled?)

    on_exit(fn ->
      restore_env(:save_it, :telegram_bot_token, previous_token)
      restore_env(:save_it, :telegram_bot_enabled?, previous_telegram_bot_enabled?)
    end)
  end

  test "is ignored when the Telegram bot is disabled" do
    Application.put_env(:save_it, :telegram_bot_enabled?, false)
    Application.delete_env(:save_it, :telegram_bot_token)

    assert :ignore = SaveIt.BotSupervisor.start_link()
  end

  test "fails fast when enabled and Telegram bot token is missing" do
    Application.put_env(:save_it, :telegram_bot_enabled?, true)
    Application.delete_env(:save_it, :telegram_bot_token)

    assert_raise RuntimeError, ~r/TELEGRAM_BOT_TOKEN must be set/, fn ->
      SaveIt.BotSupervisor.start_link()
    end
  end

  test "defaults to enabled when the Telegram bot flag is not configured" do
    Application.delete_env(:save_it, :telegram_bot_enabled?)
    Application.delete_env(:save_it, :telegram_bot_token)

    assert_raise RuntimeError, ~r/TELEGRAM_BOT_TOKEN must be set/, fn ->
      SaveIt.BotSupervisor.start_link()
    end
  end

  test "fails fast when enabled and Telegram bot token is blank" do
    Application.put_env(:save_it, :telegram_bot_enabled?, true)
    Application.put_env(:save_it, :telegram_bot_token, "  ")

    assert_raise RuntimeError, ~r/TELEGRAM_BOT_TOKEN must be set/, fn ->
      SaveIt.BotSupervisor.start_link()
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
