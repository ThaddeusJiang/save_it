defmodule SmallSdk.TypesenseAdmin do
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
      %{"name" => "url", "type" => "string"},
      # chat.id -> string
      %{"name" => "belongs_to_id", "type" => "string"},
      # unix timestamp
      %{"name" => "inserted_at", "type" => "int64"}
    ],
    "default_sorting_field" => "inserted_at"
  }

  def reset() do
    delete_collection!(@photos_schema["name"])
    create_collection!(@photos_schema)
  end

  def create_collection!(schema) do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "/collections",
        headers: [
          {"Content-Type", "application/json"},
          {"X-TYPESENSE-API-KEY", api_key}
        ]
      )

    {:ok, res} = Req.post(req, json: schema)

    res.body
  end

  def delete_collection!(collection_name) do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "/collections/#{collection_name}",
        headers: [
          {"Content-Type", "application/json"},
          {"X-TYPESENSE-API-KEY", api_key}
        ]
      )

    {:ok, res} = Req.delete(req)

    res.body
  end

  defp get_env() do
    url = Application.fetch_env!(:save_it, :typesense_url)
    api_key = Application.fetch_env!(:save_it, :typesense_api_key)

    {url, api_key}
  end
end
