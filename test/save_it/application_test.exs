defmodule SaveIt.ApplicationTest do
  use ExUnit.Case, async: false

  test "starts shared services without the Telegram bot in test" do
    assert Process.whereis(SaveIt.TaskRunner.supervisor())
    refute Process.whereis(SaveIt.BotSupervisor)
  end
end
