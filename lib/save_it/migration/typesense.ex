defmodule SaveIt.Migration.Typesense do
  alias SmallSdk.Typesense

  import SaveIt.SmallHelper.UrlHelper, only: [validate_url!: 1]

  def create_collection!(schema) do
    req = build_request("/collections")
    res = Req.post!(req, json: schema)

    Typesense.handle_response!(res)
  end

  def update_collection!(collection_name, schema) do
    req = build_request("/collections/#{collection_name}")
    res = Req.patch!(req, json: schema)

    Typesense.handle_response!(res)
  end

  def list_collections!() do
    req = build_request("/collections")
    res = Req.get!(req)

    Typesense.handle_response!(res)
  end

  def delete_collection!(collection_name) do
    req = build_request("/collections/#{collection_name}")
    res = Req.delete!(req)

    Typesense.handle_response!(res)
  end

  defp get_env() do
    url = Application.fetch_env!(:save_it, :typesense_url) |> validate_url!()

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
