defmodule SaveIt.ApplicationTest do
  use ExUnit.Case, async: false

  test "starts without the Telegram bot in test" do
    refute Process.whereis(SaveIt.BotSupervisor)
  end
end
