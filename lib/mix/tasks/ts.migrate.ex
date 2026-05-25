defmodule Mix.Tasks.Ts.Migrate do
  @moduledoc false

  use Mix.Task

  alias Req.TransportError
  alias SmallSdk.Typesense

  @shortdoc "Run Typesense collection migrations"

  @impl Mix.Task
  def run(_args) do
    boot_runtime_dependencies!()
    migration = load_photo_migration!()

    typesense_url = Application.fetch_env!(:save_it, :typesense_url)

    try do
      ensure_photos_collection!(migration)
      migrate_photos_if_needed!(migration)
      restore_photos_url_if_needed!(migration)

      Mix.shell().info("Typesense migration done")
    rescue
      error in TransportError ->
        handle_transport_error!(error, typesense_url, migration)
    end
  end

  defp ensure_photos_collection!(migration) do
    case photos_collection() do
      nil ->
        Mix.shell().info("creating photos collection")
        invoke_migration!(migration, :create_photos_20241024!)

      _collection ->
        Mix.shell().info("photos collection already exists, skipping create")
    end
  end

  defp migrate_photos_if_needed!(migration) do
    case photos_collection() do
      nil ->
        :ok

      collection ->
        if has_field?(collection, "file_id") do
          Mix.shell().info("photos migration already applied, skipping")
        else
          Mix.shell().info("applying photos migration 20241029")
          invoke_migration!(migration, :migrate_photos_20241029!)
        end
    end
  end

  defp restore_photos_url_if_needed!(migration) do
    case photos_collection() do
      nil ->
        :ok

      collection ->
        if has_field?(collection, "url") do
          Mix.shell().info("photos url field already present, skipping")
        else
          Mix.shell().info("restoring optional photos url field")
          invoke_migration!(migration, :migrate_photos_20260524!)
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

  defp boot_runtime_dependencies! do
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    Application.ensure_all_started(:req)
  end

  defp handle_transport_error!(error, typesense_url, migration) do
    if timed_out?(error) and photos_collection() != nil do
      Mix.shell().info(
        "Typesense request timed out, but the photos collection now exists. Continuing migration reconciliation."
      )

      migrate_photos_if_needed!(migration)
      restore_photos_url_if_needed!(migration)
      Mix.shell().info("Typesense migration done")
    else
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

  defp timed_out?(error) do
    Exception.message(error)
    |> String.downcase()
    |> String.contains?("timeout")
  end

  defp invoke_migration!(migration, function_name) do
    Function.capture(migration, function_name, 0).()
  end

  defp load_photo_migration! do
    path = Path.join(File.cwd!(), "priv/typesense/migrate.exs")
    Code.require_file(path)
    SaveIt.TypesensePhotoMigration
  end
end
