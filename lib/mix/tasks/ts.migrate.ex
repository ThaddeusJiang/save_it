defmodule Mix.Tasks.Ts.Migrate do
  use Mix.Task

  alias SaveIt.Migration.Typesense

  @shortdoc "Run Typesense collection migrations"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Typesense.migrate!()
  end
end
