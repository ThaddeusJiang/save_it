defmodule SmallSdk.TypesenseMigration do
  @moduledoc false

  require Logger

  alias Req.TransportError
  alias SmallSdk.Typesense

  @default_migration_collection "typesense_migrations"
  @default_migrations_path Path.expand("priv/typesense/migrations", File.cwd!())

  def migrate!(opts \\ []) do
    ensure_migration_collection!(opts)

    opts
    |> load_migrations!()
    |> Enum.each(&apply_migration!(&1, opts))
  end

  def rollback!(version, opts \\ [])

  def rollback!(nil, opts) do
    ensure_migration_collection!(opts)

    case applied_migrations(opts) |> List.last() do
      nil ->
        raise "No applied Typesense migration found"

      migration ->
        rollback_migration!(migration, [recorded?: true], opts)
    end
  end

  def rollback!(version, opts) when is_binary(version) do
    ensure_migration_collection!(opts)

    normalized_version = normalize_version!(version)
    migration = fetch_migration!(normalized_version, opts)
    applied_versions = applied_versions(opts)

    cond do
      normalized_version in applied_versions and List.last(applied_versions) != normalized_version ->
        raise "Typesense migration #{normalized_version} is not the latest applied migration"

      normalized_version in applied_versions ->
        rollback_migration!(migration, [recorded?: true], opts)

      true ->
        rollback_migration!(migration, [recorded?: false], opts)
    end
  end

  def reset!(opts \\ []) do
    client = client(opts)

    opts
    |> Keyword.get(:managed_collections, [])
    |> Enum.each(&client.delete_collection/1)

    client.delete_collection(migration_collection(opts))

    migrate!(opts)
  end

  def run_up!(version, opts \\ []) when is_binary(version) do
    version
    |> normalize_version!()
    |> fetch_migration!(opts)
    |> invoke_up!(opts)
  end

  def run_down!(version, opts \\ []) when is_binary(version) do
    version
    |> normalize_version!()
    |> fetch_migration!(opts)
    |> invoke_down!(opts)
  end

  def create_collection!(schema, opts \\ []) when is_map(schema) do
    client(opts).create_collection!(schema)
  end

  def update_collection!(collection_name, schema, opts \\ [])
      when is_binary(collection_name) and is_map(schema) do
    client(opts).update_collection!(collection_name, schema)
  end

  def delete_collection(collection_name, opts \\ []) when is_binary(collection_name) do
    client(opts).delete_collection(collection_name)
  end

  def list_documents(collection_name, list_opts \\ [], opts \\ [])
      when is_binary(collection_name) do
    client(opts).list_documents(collection_name, list_opts)
  end

  def update_document!(collection_name, document_id, update_input, opts \\ [])
      when is_binary(collection_name) and is_binary(document_id) and is_map(update_input) do
    client(opts).update_document!(collection_name, document_id, update_input)
  end

  def collection(name, opts \\ []) when is_binary(name) do
    client(opts).list_collections!()
    |> Enum.find(fn collection -> collection["name"] == name end)
  end

  def has_field?(collection_name, field_name, opts \\ [])
      when is_binary(collection_name) and is_binary(field_name) do
    field(collection_name, field_name, opts) != nil
  end

  def field(collection_name, field_name, opts \\ [])
      when is_binary(collection_name) and is_binary(field_name) do
    case collection(collection_name, opts) do
      nil ->
        nil

      collection ->
        collection
        |> Map.get("fields", [])
        |> Enum.find(fn field -> field["name"] == field_name end)
    end
  end

  def load_migrations!(opts \\ []) do
    opts
    |> migrations_path()
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&require_migration_file/1)
    |> Enum.uniq()
    |> Enum.filter(&migration_module?/1)
    |> Enum.sort_by(&Function.capture(&1, :version, 0).())
  end

  defp require_migration_file(path) do
    case Code.require_file(path) do
      nil -> loaded_modules_from_file(path)
      modules -> Enum.map(modules, fn {module, _bytecode} -> module end)
    end
  end

  defp loaded_modules_from_file(path) do
    expanded_path = Path.expand(path)

    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> Enum.filter(&(module_source(&1) == expanded_path))
  end

  defp module_source(module) do
    case module.module_info(:compile) |> Keyword.get(:source) do
      nil -> nil
      source -> source |> to_string() |> Path.expand()
    end
  rescue
    _error -> nil
  end

  defp migration_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :version, 0) and
      function_exported?(module, :name, 0) and
      function_exported?(module, :up, 0) and
      function_exported?(module, :down, 0) and
      function_exported?(module, :applied?, 0)
  end

  defp ensure_migration_collection!(opts) do
    migration_collection = migration_collection(opts)

    case collection(migration_collection, opts) do
      nil ->
        client(opts).create_collection!(%{
          "name" => migration_collection,
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
      if timed_out?(error) and collection(migration_collection(opts), opts) != nil do
        Logger.info(
          "Typesense migration collection creation timed out, but the collection now exists. Continuing."
        )

        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp apply_migration!(migration, opts) do
    version = migration.version()
    name = migration.name()

    cond do
      version in applied_versions(opts) ->
        Logger.info("Typesense migration #{version} #{name} already recorded, skipping")

      migration.applied?() ->
        Logger.info("Typesense migration #{version} #{name} already applied, recording")
        record_migration!(migration, opts)

      true ->
        Logger.info("Applying Typesense migration #{version} #{name}")
        invoke_up!(migration, opts)
        record_migration!(migration, opts)
    end
  end

  defp rollback_migration!(migration, rollback_opts, opts) do
    version = migration.version()
    name = migration.name()

    Logger.info("Rolling back Typesense migration #{version} #{name}")
    invoke_down!(migration, opts)

    if Keyword.fetch!(rollback_opts, :recorded?) do
      delete_migration_record!(version, opts)
    end
  end

  defp invoke_up!(migration, _opts) do
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

  defp invoke_down!(migration, _opts) do
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

  defp applied_migrations(opts) do
    applied_versions = applied_versions(opts)

    opts
    |> load_migrations!()
    |> Enum.filter(fn migration -> migration.version() in applied_versions end)
  end

  defp applied_versions(opts) do
    opts
    |> migration_collection()
    |> client(opts).list_documents(per_page: 200, query_by: "name")
    |> Enum.map(&Map.fetch!(&1, "id"))
    |> Enum.sort()
  end

  defp record_migration!(migration, opts) do
    version = migration.version()

    unless version in applied_versions(opts) do
      client(opts).create_document!(migration_collection(opts), %{
        "id" => version,
        "name" => migration.name(),
        "applied_at" => DateTime.utc_now() |> DateTime.to_unix()
      })
    end
  end

  defp delete_migration_record!(version, opts) do
    client(opts).delete_document(migration_collection(opts), version)
    :ok
  end

  defp fetch_migration!(version, opts) do
    opts
    |> load_migrations!()
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

  defp client(opts), do: Keyword.get(opts, :client, Typesense)

  defp migration_collection(opts),
    do: Keyword.get(opts, :migration_collection, @default_migration_collection)

  defp migrations_path(opts), do: Keyword.get(opts, :migrations_path, @default_migrations_path)

  defp timed_out?(error) do
    Exception.message(error)
    |> String.downcase()
    |> String.contains?("timeout")
  end
end
