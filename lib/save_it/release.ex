defmodule SaveIt.Release do
  @moduledoc false

  alias SaveIt.Migration.Typesense

  def ts_migrate do
    ensure_runtime_dependencies!()
    Typesense.migrate!()
  end

  defp ensure_runtime_dependencies! do
    Application.load(:save_it)

    case Application.ensure_all_started(:req) do
      {:ok, _started} -> :ok
      {:error, reason} -> raise "failed to start release migration dependencies: #{inspect(reason)}"
    end
  end
end
