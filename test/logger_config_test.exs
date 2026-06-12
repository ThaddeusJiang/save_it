defmodule SaveIt.LoggerConfigTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  @tesla_logger_config Application.compile_env(:tesla, Tesla.Middleware.Logger, [])
  @runtime_config Path.expand("../config/runtime.exs", __DIR__)

  defmodule TeslaTestAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      {:ok, %Tesla.Env{env | status: 200, body: %{ok: true, result: %{created: 1}}}}
    end
  end

  test "Tesla HTTP logger does not dump full request and response bodies at debug level" do
    assert @tesla_logger_config[:debug] == false
  end

  test "Tesla HTTP logger keeps debug output at request summary level" do
    log =
      capture_log([level: :debug], fn ->
        client = Tesla.client([{Tesla.Middleware.Logger, []}], TeslaTestAdapter)

        assert {:ok, %Tesla.Env{status: 200}} =
                 Tesla.post(client, "https://example.test/save", %{message_id: 3974})
      end)

    assert log =~ "POST https://example.test/save -> 200"
    refute log =~ ">>> REQUEST >>>"
    refute log =~ "%{message_id: 3974}"
    refute log =~ "%{ok: true"
  end

  test "runtime logger uses distinct severity colors" do
    logger_config = Application.fetch_env!(:logger, :default_formatter)

    assert logger_config[:colors][:info] == :green
    assert logger_config[:colors][:warning] == :yellow
    assert logger_config[:colors][:error] == :red
  end

  test "runtime config requires the Telegram bot token and shares it with ExGram" do
    previous_system_token = System.get_env("TELEGRAM_BOT_TOKEN")

    on_exit(fn ->
      restore_system_env("TELEGRAM_BOT_TOKEN", previous_system_token)
    end)

    System.put_env("TELEGRAM_BOT_TOKEN", "required-token")
    runtime_config = Config.Reader.read!(@runtime_config, env: Mix.env())

    assert get_in(runtime_config, [:save_it, :telegram_bot_token]) == "required-token"
    assert get_in(runtime_config, [:ex_gram, :token]) == "required-token"

    System.delete_env("TELEGRAM_BOT_TOKEN")

    test_runtime_config = Config.Reader.read!(@runtime_config, env: :test)

    assert get_in(test_runtime_config, [:save_it, :telegram_bot_token]) == "test-token"
    assert get_in(test_runtime_config, [:ex_gram, :token]) == "test-token"

    assert_raise System.EnvError, fn ->
      Config.Reader.read!(@runtime_config, env: :dev)
    end
  end

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
