defmodule SmallSdk.TypesenseMigrationTest do
  use ExUnit.Case, async: true

  defmodule FakeTypesense do
    def create_collection!(schema) do
      send(Process.get(:typesense_migration_test_pid), {:create_collection, schema})
      schema
    end

    def update_collection!(collection_name, schema) do
      send(
        Process.get(:typesense_migration_test_pid),
        {:update_collection, collection_name, schema}
      )

      schema
    end

    def delete_collection(collection_name) do
      send(Process.get(:typesense_migration_test_pid), {:delete_collection, collection_name})
      nil
    end

    def list_collections! do
      []
    end

    def list_documents(collection_name, opts) do
      send(Process.get(:typesense_migration_test_pid), {:list_documents, collection_name, opts})
      []
    end

    def update_document!(collection_name, document_id, update_input) do
      send(
        Process.get(:typesense_migration_test_pid),
        {:update_document, collection_name, document_id, update_input}
      )

      update_input
    end
  end

  test "reset deletes only configured managed collections before rerunning migrations" do
    Process.put(:typesense_migration_test_pid, self())

    SmallSdk.TypesenseMigration.reset!(
      client: FakeTypesense,
      migrations_path: empty_migrations_path(),
      managed_collections: ["photos"]
    )

    assert_receive {:delete_collection, "photos"}
    assert_receive {:delete_collection, "typesense_migrations"}
    assert_receive {:create_collection, %{"name" => "typesense_migrations"}}
    refute_received {:delete_collection, "videos"}
  end

  test "reset does not assume an application collection by default" do
    Process.put(:typesense_migration_test_pid, self())

    SmallSdk.TypesenseMigration.reset!(
      client: FakeTypesense,
      migrations_path: empty_migrations_path()
    )

    assert_receive {:delete_collection, "typesense_migrations"}
    refute_received {:delete_collection, "photos"}
  end

  test "exposes migration-scoped collection and document operations" do
    Process.put(:typesense_migration_test_pid, self())
    opts = [client: FakeTypesense]

    assert SmallSdk.TypesenseMigration.create_collection!(%{"name" => "photos"}, opts) == %{
             "name" => "photos"
           }

    assert SmallSdk.TypesenseMigration.update_collection!("photos", %{"fields" => []}, opts) == %{
             "fields" => []
           }

    assert SmallSdk.TypesenseMigration.delete_collection("photos", opts) == nil
    assert SmallSdk.TypesenseMigration.list_documents("photos", [per_page: 10], opts) == []

    assert SmallSdk.TypesenseMigration.update_document!("photos", "1", %{"file_id" => "1"}, opts) ==
             %{"file_id" => "1"}

    assert_receive {:create_collection, %{"name" => "photos"}}
    assert_receive {:update_collection, "photos", %{"fields" => []}}
    assert_receive {:delete_collection, "photos"}
    assert_receive {:list_documents, "photos", [per_page: 10]}
    assert_receive {:update_document, "photos", "1", %{"file_id" => "1"}}
  end

  test "loads only migration modules required from the configured migrations path" do
    migrations_path = migrations_path_with_migration()

    assert [loaded_migration] =
             SmallSdk.TypesenseMigration.load_migrations!(migrations_path: migrations_path)

    assert loaded_migration.version() == "20260613000000"

    assert SmallSdk.TypesenseMigration.load_migrations!(migrations_path: empty_migrations_path()) ==
             []
  end

  defp empty_migrations_path do
    path = Path.join(System.tmp_dir!(), "save-it-empty-migrations-#{System.unique_integer()}")
    File.mkdir_p!(path)
    path
  end

  defp migrations_path_with_migration do
    path = Path.join(System.tmp_dir!(), "save-it-migrations-#{System.unique_integer()}")
    File.mkdir_p!(path)

    File.write!(Path.join(path, "20260613000000_loaded_migration.exs"), """
    defmodule SaveIt.Typesense.Migrations.LoadedMigration20260613000000 do
      def version, do: "20260613000000"
      def name, do: "loaded_migration"
      def up, do: :ok
      def down, do: :ok
      def applied?, do: false
    end
    """)

    path
  end
end
