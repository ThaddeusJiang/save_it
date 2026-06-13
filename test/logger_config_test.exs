defmodule SaveIt.LoggerConfigTest do
  use ExUnit.Case, async: true

  @runtime_config Path.expand("../config/runtime.exs", __DIR__)

  test "runtime logger uses distinct severity colors" do
    assert Application.fetch_env!(:logger, :level) == :info

    logger_config = Application.fetch_env!(:logger, :default_formatter)

    assert logger_config[:metadata] == [:status, :file_id, :kind]
    assert logger_config[:colors][:info] == :green
    assert logger_config[:colors][:warning] == :yellow
    assert logger_config[:colors][:error] == :red
  end

  test "runtime config shares the Telegram bot token with ExGram" do
    previous_system_token = System.get_env("TELEGRAM_BOT_TOKEN")

    on_exit(fn ->
      restore_system_env("TELEGRAM_BOT_TOKEN", previous_system_token)
    end)

    System.put_env("TELEGRAM_BOT_TOKEN", "required-token")
    runtime_config = Config.Reader.read!(@runtime_config, env: Mix.env())

    assert get_in(runtime_config, [:save_it, :telegram_bot_token]) == "required-token"
    assert get_in(runtime_config, [:ex_gram, :token]) == "required-token"
    assert get_in(runtime_config, [:ex_gram, :adapter]) == ExGram.Adapter.Req
  end

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
