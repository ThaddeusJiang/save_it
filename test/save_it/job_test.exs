defmodule SaveIt.JobTest do
  use ExUnit.Case, async: true

  alias SaveIt.Job

  test "runs a callback after the configured delay" do
    parent = self()

    assert :ok = Job.run_after(0, fn -> send(parent, :job_ran) end)

    assert_receive :job_ran
  end
end
