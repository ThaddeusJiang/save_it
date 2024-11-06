defmodule SaveIt.Migration.Typesense.Photo do
  require Logger
  alias SaveIt.Migration.Typesense

  alias SmallSdk.Typesense, as: TypesenseDataClient

  @collection_name "photos"

  def create_photos_20241024!() do
    schema = %{
      "name" => @collection_name,
      "fields" => [
        %{"name" => "image", "type" => "image", "store" => false},
        %{
          "name" => "image_embedding",
          "type" => "float[]",
          "embed" => %{
            "from" => ["image"],
            "model_config" => %{
              "model_name" => "ts/clip-vit-b-p32"
            }
          }
        },
        %{"name" => "caption", "type" => "string", "optional" => true},
        %{"name" => "url", "type" => "string"},
        %{"name" => "belongs_to_id", "type" => "string"},
        %{"name" => "inserted_at", "type" => "int64"}
      ],
      "default_sorting_field" => "inserted_at"
    }

    Typesense.create_collection!(schema)
  end

  def migrate_photos_20241029!() do
    Logger.info("updating photos collection")

    Typesense.update_collection!(@collection_name, %{
      "fields" => [
        %{"name" => "file_id", "type" => "string", "optional" => true},
        %{"name" => "url", "drop" => true}
      ]
    })
  end

  def migrate_photos_data_20241029 do
    Logger.info("migrating photos documents")

    docs =
      TypesenseDataClient.list_documents(@collection_name, per_page: 200)

    count =
      Enum.map(docs, fn doc ->
        id = doc["id"]

        file_id =
          doc["url"]
          |> String.split("/")
          |> List.last()

        TypesenseDataClient.update_document!(@collection_name, id, %{
          "file_id" => file_id
        })
      end)
      |> Enum.count()

    Logger.info("migrated #{count} photos")
  end

  def drop_photos() do
    Typesense.delete_collection(@collection_name)
  end

  def reset!() do
    drop_photos()
    create_photos_20241024!()
    migrate_photos_20241029!()
  end
end
