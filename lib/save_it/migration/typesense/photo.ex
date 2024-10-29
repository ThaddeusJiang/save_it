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

  def migrate_photos_2024_10_29!() do
    Logger.info("updating photos collection")

    Typesense.update_collection!(@collection_name, %{
      "fields" => [
        %{"name" => "file_id", "type" => "string"}
      ]
    })

    Logger.info("migrating photos data")

    TypesenseDataClient.list_documents(@collection_name, per_page: 10000)
    |> Enum.each(fn doc ->
      id = doc["id"]

      file_id =
        doc["url"]
        |> String.split("/")
        |> List.last()

      TypesenseDataClient.update_document!(@collection_name, id, %{
        "file_id" => file_id
      })
    end)

    Logger.info("dropping url field")

    Typesense.update_collection!(@collection_name, %{
      "fields" => [
        %{"name" => "url", "drop" => true}
      ]
    })
  end

  def drop_photos!() do
    Typesense.delete_collection!(@collection_name)
  end

  def reset!() do
    drop_photos!()
    create_photos_20241024!()
    migrate_photos_2024_10_29!()
  end
end
