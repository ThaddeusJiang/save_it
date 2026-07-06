defmodule SaveIt.TaskRunnerTest do
  use ExUnit.Case, async: false

  defmodule Probe do
    def notify(test_pid, payload) do
      send(test_pid, {:task_runner_called, payload})
    end
  end

  test "runs a module function asynchronously under a supervised task" do
    assert {:ok, pid} = SaveIt.TaskRunner.run(Probe, :notify, [self(), :ok])
    assert is_pid(pid)

    assert_receive {:task_runner_called, :ok}
  end

  test "exposes the default task supervisor name" do
    assert Process.whereis(SaveIt.TaskRunner.supervisor())
  end
end
