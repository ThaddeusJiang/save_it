# mix run priv/typesense/reset.exs

Code.require_file("migrate.exs", __DIR__)

SaveIt.TypesensePhotoMigration.reset!()
