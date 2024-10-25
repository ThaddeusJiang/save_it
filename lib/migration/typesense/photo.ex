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
      # "telegram://<bot_id>/<file_id>"
      # TODO: 不能再简单的 reset 了，reset 会导致数据丢失，应该合理 migrate 数据
      %{"name" => "url", "type" => "string"},
      # chat.id -> string
      %{"name" => "belongs_to_id", "type" => "string"},
      # unix timestamp
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
