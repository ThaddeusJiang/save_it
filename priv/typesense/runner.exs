defmodule SmallSdk.TypesenseMigration.Runner do
  @moduledoc false

  def run(args) do
    root = File.cwd!()

    require_file_unless_loaded(SmallSdk.Typesense, Path.join(root, "lib/small_sdk/typesense.ex"))

    require_file_unless_loaded(
      SmallSdk.TypesenseMigration,
      Path.join(root, "lib/small_sdk/typesense_migration.ex")
    )

    Application.put_env(
      :save_it,
      :typesense_url,
      System.get_env("TYPESENSE_URL", "http://localhost:8108")
    )

    Application.put_env(:save_it, :typesense_api_key, System.get_env("TYPESENSE_API_KEY", "xyz"))

    Application.ensure_all_started(:req)

    opts = [
      migrations_path: Path.join(root, "priv/typesense/migrations")
    ]

    case args do
      ["migrate"] ->
        apply(SmallSdk.TypesenseMigration, :migrate!, [opts])
        Mix.shell().info("Typesense migration done")

      ["rollback"] ->
        apply(SmallSdk.TypesenseMigration, :rollback!, [nil, opts])
        Mix.shell().info("Typesense rollback done")

      ["rollback", version] ->
        apply(SmallSdk.TypesenseMigration, :rollback!, [version, opts])
        Mix.shell().info("Typesense rollback done")

      ["reset"] ->
        opts = Keyword.put(opts, :managed_collections, ["photos"])
        Mix.shell().info("resetting photos collection")
        apply(SmallSdk.TypesenseMigration, :reset!, [opts])
        Mix.shell().info("Typesense reset done")

      _args ->
        Mix.raise("Usage: mix ts.migrate | mix ts.rollback [VERSION] | mix ts.reset")
    end
  end

  defp require_file_unless_loaded(module, path) do
    unless Code.ensure_loaded?(module) do
      Code.require_file(path)
    end
  end
end
