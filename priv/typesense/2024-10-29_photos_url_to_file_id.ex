# mix run priv/typesense/2024-10-29_photos_url_to_file_id.ex
Code.require_file("migrate.exs", __DIR__)

SaveIt.TypesensePhotoMigration.migrate_photos_20241029!()
