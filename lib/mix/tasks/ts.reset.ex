defmodule Mix.Tasks.Ts.Reset do
  use Mix.Task

  alias SaveIt.Migration.Typesense.Photo

  @shortdoc "Reset Typesense photos collection"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("resetting photos collection")
    Photo.reset!()

    Mix.shell().info("Typesense reset done")
  end
end
