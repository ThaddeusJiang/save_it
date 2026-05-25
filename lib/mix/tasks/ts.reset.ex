defmodule Mix.Tasks.Ts.Reset do
  @moduledoc false

  use Mix.Task

  @shortdoc "Reset Typesense photos collection"

  @impl Mix.Task
  def run(_args) do
    boot_runtime_dependencies!()
    migration = load_photo_migration!()

    Mix.shell().info("resetting photos collection")
    Function.capture(migration, :reset!, 0).()

    Mix.shell().info("Typesense reset done")
  end

  defp boot_runtime_dependencies! do
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    Application.ensure_all_started(:req)
  end

  defp load_photo_migration! do
    path = Path.join(File.cwd!(), "priv/typesense/migrate.exs")
    Code.require_file(path)
    SaveIt.TypesensePhotoMigration
  end
end
