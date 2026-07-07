defmodule SaveIt.Job do
  @moduledoc false

  def run_after(delay_ms, fun)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(fun, 0) do
    Task.start(fn ->
      if delay_ms > 0, do: Process.sleep(delay_ms)

      fun.()
    end)

    :ok
  end
end
