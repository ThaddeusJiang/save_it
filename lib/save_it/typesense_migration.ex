defmodule SaveIt.TypesenseMigration do
  @moduledoc false

  require Logger

  alias Req.TransportError
  alias SmallSdk.Typesense

  @migration_collection "typesense_migrations"
  @migrations_path Path.expand("../../priv/typesense/migrations", __DIR__)

  def migrate! do
    ensure_migration_collection!()

    load_migrations!()
    |> Enum.each(&apply_migration!/1)
  end

  def rollback!(nil) do
    ensure_migration_collection!()

    case applied_migrations() |> List.last() do
      nil ->
        raise "No applied Typesense migration found"

      migration ->
        rollback_migration!(migration, recorded?: true)
    end
  end

  def rollback!(version) when is_binary(version) do
    ensure_migration_collection!()

    normalized_version = normalize_version!(version)
    migration = fetch_migration!(normalized_version)
    applied_versions = applied_versions()

    cond do
      normalized_version in applied_versions and List.last(applied_versions) != normalized_version ->
        raise "Typesense migration #{normalized_version} is not the latest applied migration"

      normalized_version in applied_versions ->
        rollback_migration!(migration, recorded?: true)

      true ->
        rollback_migration!(migration, recorded?: false)
    end
  end

  def reset! do
    Typesense.delete_collection("photos")
    Typesense.delete_collection(@migration_collection)

    migrate!()
  end

  def run_up!(version) when is_binary(version) do
    version
    |> normalize_version!()
    |> fetch_migration!()
    |> invoke_up!()
  end

  def run_down!(version) when is_binary(version) do
    version
    |> normalize_version!()
    |> fetch_migration!()
    |> invoke_down!()
  end

  def collection(name) when is_binary(name) do
    Typesense.list_collections!()
    |> Enum.find(fn collection -> collection["name"] == name end)
  end

  def has_field?(collection_name, field_name)
      when is_binary(collection_name) and is_binary(field_name) do
    field(collection_name, field_name) != nil
  end

  def field(collection_name, field_name)
      when is_binary(collection_name) and is_binary(field_name) do
    case collection(collection_name) do
      nil ->
        nil

      collection ->
        collection
        |> Map.get("fields", [])
        |> Enum.find(fn field -> field["name"] == field_name end)
    end
  end

  def load_migrations! do
    @migrations_path
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.each(&Code.require_file/1)
    |> then(fn _ ->
      :code.all_loaded()
      |> Enum.map(fn {module, _path} -> module end)
    end)
    |> Enum.filter(&migration_module?/1)
    |> Enum.sort_by(&Function.capture(&1, :version, 0).())
  end

  defp migration_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :version, 0) and
      function_exported?(module, :name, 0) and
      function_exported?(module, :up, 0) and
      function_exported?(module, :down, 0) and
      function_exported?(module, :applied?, 0)
  end

  defp ensure_migration_collection! do
    case collection(@migration_collection) do
      nil ->
        Typesense.create_collection!(%{
          "name" => @migration_collection,
          "fields" => [
            %{"name" => "name", "type" => "string"},
            %{"name" => "applied_at", "type" => "int64"}
          ],
          "default_sorting_field" => "applied_at"
        })

      _collection ->
        :ok
    end
  rescue
    error in TransportError ->
      if timed_out?(error) and collection(@migration_collection) != nil do
        Logger.info(
          "Typesense migration collection creation timed out, but the collection now exists. Continuing."
        )

        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp apply_migration!(migration) do
    version = migration.version()
    name = migration.name()

    cond do
      version in applied_versions() ->
        Logger.info("Typesense migration #{version} #{name} already recorded, skipping")

      migration.applied?() ->
        Logger.info("Typesense migration #{version} #{name} already applied, recording")
        record_migration!(migration)

      true ->
        Logger.info("Applying Typesense migration #{version} #{name}")
        invoke_up!(migration)
        record_migration!(migration)
    end
  end

  defp rollback_migration!(migration, opts) do
    version = migration.version()
    name = migration.name()

    Logger.info("Rolling back Typesense migration #{version} #{name}")
    invoke_down!(migration)

    if Keyword.fetch!(opts, :recorded?) do
      delete_migration_record!(version)
    end
  end

  defp invoke_up!(migration) do
    migration.up()
  rescue
    error in TransportError ->
      if timed_out?(error) and migration.applied?() do
        Logger.info(
          "Typesense migration #{migration.version()} timed out, but the target state is already visible. Continuing."
        )

        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp invoke_down!(migration) do
    migration.down()
  rescue
    error in TransportError ->
      if timed_out?(error) and not migration.applied?() do
        Logger.info(
          "Typesense rollback #{migration.version()} timed out, but the target state is already reverted. Continuing."
        )

        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp applied_migrations do
    applied_versions = applied_versions()

    load_migrations!()
    |> Enum.filter(fn migration -> migration.version() in applied_versions end)
  end

  defp applied_versions do
    Typesense.list_documents(@migration_collection, per_page: 200, query_by: "name")
    |> Enum.map(&Map.fetch!(&1, "id"))
    |> Enum.sort()
  end

  defp record_migration!(migration) do
    version = migration.version()

    unless version in applied_versions() do
      Typesense.create_document!(@migration_collection, %{
        "id" => version,
        "name" => migration.name(),
        "applied_at" => DateTime.utc_now() |> DateTime.to_unix()
      })
    end
  end

  defp delete_migration_record!(version) do
    Typesense.delete_document(@migration_collection, version)
    :ok
  end

  defp fetch_migration!(version) do
    load_migrations!()
    |> Enum.find(fn migration -> migration.version() == version end)
    |> case do
      nil -> raise "Unknown Typesense migration #{version}"
      migration -> migration
    end
  end

  defp normalize_version!(version) do
    normalized_version =
      version
      |> String.trim()
      |> String.replace(~r/[^0-9]/, "")

    if normalized_version == "" do
      raise "Invalid Typesense migration version #{inspect(version)}"
    end

    normalized_version
  end

  defp timed_out?(error) do
    Exception.message(error)
    |> String.downcase()
    |> String.contains?("timeout")
  end
end
