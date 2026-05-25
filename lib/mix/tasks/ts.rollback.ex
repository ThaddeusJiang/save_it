defmodule Mix.Tasks.Ts.Rollback do
  @moduledoc false

  use Mix.Task

  alias SaveIt.TypesenseMigration

  @shortdoc "Rollback the latest or selected Typesense migration"

  @impl Mix.Task
  def run(args) do
    boot_runtime_dependencies!()

    case args do
      [] ->
        TypesenseMigration.rollback!(nil)

      [version] ->
        TypesenseMigration.rollback!(version)

      _ ->
        Mix.raise("Usage: mix ts.rollback [VERSION]")
    end

    Mix.shell().info("Typesense rollback done")
  end

  defp boot_runtime_dependencies! do
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    Application.ensure_all_started(:req)
  end
end
