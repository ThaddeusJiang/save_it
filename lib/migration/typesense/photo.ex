defmodule Migration.Typesense.Photo do
  alias Migration.Typesense

  @photos_schema %{
    "name" => "photos",
    "fields" => [
      # image: base64 encoded string
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
      %{"name" => "caption", "type" => "string", "optional" => true, "facet" => false},
      %{"name" => "file_id", "type" => "string"},
      %{"name" => "belongs_to_id", "type" => "string"},
      %{"name" => "inserted_at", "type" => "int64"}
    ],
    "default_sorting_field" => "inserted_at"
  }

  def create_collection!() do
    Typesense.create_collection!(@photos_schema)
  end

  def reset!() do
    Typesense.delete_collection!(@photos_schema["name"])
    Typesense.create_collection!(@photos_schema)
  end
end
