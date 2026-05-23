defmodule Mix.Tasks.Ts.Migrate do
  use Mix.Task

  alias Req.TransportError
  alias SaveIt.Migration.Typesense
  alias SaveIt.Migration.Typesense.Photo

  @shortdoc "Run Typesense collection migrations"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    typesense_url = Application.fetch_env!(:save_it, :typesense_url)

    try do
      ensure_photos_collection!()
      migrate_photos_if_needed!()

      Mix.shell().info("Typesense migration done")
    rescue
      error in TransportError ->
        raise """
        Typesense request failed: #{Exception.message(error)}
        Current TYPESENSE_URL: #{typesense_url}

        If you are using docker-compose locally, try:
          export TYPESENSE_URL=http://localhost:8108
          docker compose up -d typesense
          mix ts.migrate
        """
    end
  end

  defp ensure_photos_collection! do
    case photos_collection() do
      nil ->
        Mix.shell().info("creating photos collection")
        Photo.create_photos_20241024!()

      _collection ->
        Mix.shell().info("photos collection already exists, skipping create")
    end
  end

  defp migrate_photos_if_needed! do
    case photos_collection() do
      nil ->
        :ok

      collection ->
        if has_field?(collection, "url") do
          Mix.shell().info("applying photos migration 20241029")
          Photo.migrate_photos_20241029!()
        else
          Mix.shell().info("photos migration already applied, skipping")
        end
    end
  end

  defp photos_collection do
    Typesense.list_collections!()
    |> Enum.find(fn collection -> collection["name"] == "photos" end)
  end

  defp has_field?(collection, field_name) do
    collection
    |> Map.get("fields", [])
    |> Enum.any?(fn field -> field["name"] == field_name end)
  end
end
