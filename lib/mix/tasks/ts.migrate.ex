defmodule Mix.Tasks.Ts.Migrate do
  @moduledoc false

  use Mix.Task

  alias SaveIt.TypesenseMigration

  @shortdoc "Run Typesense collection migrations"

  @impl Mix.Task
  def run(_args) do
    boot_runtime_dependencies!()
    TypesenseMigration.migrate!()
    Mix.shell().info("Typesense migration done")
  end

  defp boot_runtime_dependencies! do
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    Application.ensure_all_started(:req)
  end
end
