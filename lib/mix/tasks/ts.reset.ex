defmodule Mix.Tasks.Ts.Reset do
  @moduledoc false

  use Mix.Task

  alias SaveIt.TypesenseMigration

  @shortdoc "Reset Typesense photos collection"

  @impl Mix.Task
  def run(_args) do
    boot_runtime_dependencies!()

    Mix.shell().info("resetting photos collection")
    TypesenseMigration.reset!()

    Mix.shell().info("Typesense reset done")
  end

  defp boot_runtime_dependencies! do
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    Application.ensure_all_started(:req)
  end
end
