defmodule SmallSdk.Typesense do
  require Logger

  def handle_response(res) do
    case res do
      %Req.Response{status: 200} ->
        res.body

      %Req.Response{status: 201} ->
        res.body

      %Req.Response{status: 400} ->
        Logger.error("Bad Request: #{inspect(res.body)}")
        raise "Bad Request"

      %Req.Response{status: 401} ->
        raise "Unauthorized"

      %Req.Response{status: 404} ->
        nil

      %Req.Response{status: 409} ->
        raise "Conflict"

      %Req.Response{status: 422} ->
        raise "Unprocessable Entity"

      %Req.Response{status: 503} ->
        raise "Service Unavailable"

      _ ->
        raise "Unknown error"
    end
  end

  def create_document!(collection_name, document) do
    req = build_request("/collections/#{collection_name}/documents")
    {:ok, res} = Req.post(req, json: document)

    handle_response(res)
  end

  def search_documents!(collection_name, opts) do
    q = Keyword.get(opts, :q, "*")
    query_by = Keyword.get(opts, :query_by, "")
    filter_by = Keyword.get(opts, :filter_by, "")

    req = build_request("/collections/#{collection_name}/documents/search")

    {:ok, res} =
      Req.get(req,
        params: %{
          q: q,
          query_by: query_by,
          filter_by: filter_by
        }
      )

    data = handle_response(res)

    data["hits"] |> Enum.map(&Map.get(&1, "document"))
  end

  def get_document(collection_name, document_id) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    {:ok, res} = Req.get(req)

    handle_response(res)
  end

  def update_document!(collection_name, document_id, update_input) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    {:ok, res} = Req.patch(req, json: update_input)

    handle_response(res)
  end

  def create_search_key() do
    {url, _} = get_env()
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
