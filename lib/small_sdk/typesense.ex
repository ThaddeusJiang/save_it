defmodule SmallSdk.Typesense do
  require Logger

  def create_document!(collection_name, document) do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "/collections/#{collection_name}/documents",
        headers: [
          {"Content-Type", "application/json"},
          {"X-TYPESENSE-API-KEY", api_key}
        ]
      )

    {:ok, res} = Req.post(req, json: document)

    res.body
  end

  def get_document(collection_name, document_id) do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "/collections/#{collection_name}/documents/#{document_id}",
        headers: [{"X-TYPESENSE-API-KEY", api_key}],
        params: [exclude_fields: "image_embedding"]
      )

    {:ok, res} = Req.get(req)

    res.body
  end

  def update_document(collection_name, document) do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "/collections/#{collection_name}/documents/#{document[:id]}",
        headers: [
          {"Content-Type", "application/json"},
          {"X-TYPESENSE-API-KEY", api_key}
        ]
      )

    {:ok, res} = Req.patch(req, json: document)

    res.body
  end

  def create_search_key() do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "/keys",
        headers: [
          {"Content-Type", "application/json"},
          {"X-TYPESENSE-API-KEY", api_key}
        ]
      )

    {:ok, res} =
      Req.post(req,
        json: %{
          "description" => "Search-only photos key",
          "actions" => ["documents:search"],
          "collections" => ["photos"]
        }
      )

    %{
      url: url,
      api_key: res.body["value"]
    }
  end

  defp get_env() do
    url = Application.get_env(:save_it, :typesense_url)
    api_key = Application.get_env(:save_it, :typesense_api_key)

    {url, api_key}
  end
end
