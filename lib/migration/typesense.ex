defmodule Migration.Typesense do
  def list_collections() do
    req = build_request("/collections")
    {:ok, res} = Req.get(req)

    res.body
  end

  def create_collection!(schema) do
    req = build_request("/collections")
    {:ok, res} = Req.post(req, json: schema)

    res.body
  end

  def delete_collection!(collection_name) do
    req = build_request("/collections/#{collection_name}")
    {:ok, res} = Req.delete(req)

    res.body
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
