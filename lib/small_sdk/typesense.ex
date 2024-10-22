defmodule SmallSdk.Typesense do
  require Logger

  def create_document!(collection_name, document) do
    req = build_request("/collections/#{collection_name}/documents")
    {:ok, res} = Req.post(req, json: document)

    res.body
  end

  def get_document(collection_name, document_id) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    {:ok, res} = Req.get(req)

    res.body
  end

  def update_document(collection_name, document_id, update_input) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    {:ok, res} = Req.patch(req, json: update_input)

    res.body
  end

  def create_search_key() do
    req = build_request("/keys")

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
    url = Application.fetch_env!(:save_it, :typesense_url)
    api_key = Application.fetch_env!(:save_it, :typesense_api_key)

    {url, api_key}
  end

  defp build_request(path) do
    {url, api_key} = get_env()

    Req.new(
      base_url: url,
      url: path,
      headers: [
        {"Content-Type", "application/json"},
        {"X-TYPESENSE-API-KEY", api_key}
      ]
    )
  end
end
