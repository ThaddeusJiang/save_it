defmodule SaveIt.Typesense.Migrations.CreatePhotosCollection20241024000000 do
  @moduledoc false

  alias SaveIt.TypesenseMigration
  alias SmallSdk.Typesense

  @collection_name "photos"

  def version, do: "20241024000000"
  def name, do: "create_photos_collection"

  def up do
    case TypesenseMigration.collection(@collection_name) do
      nil ->
        Typesense.create_collection!(%{
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
        })

      _collection ->
        :ok
    end
  end

  def down do
    Typesense.delete_collection(@collection_name)
    :ok
  end

  def applied? do
    TypesenseMigration.collection(@collection_name) != nil
  end
end
