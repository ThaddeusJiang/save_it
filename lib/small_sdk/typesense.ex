defmodule SmallSdk.Typesense do
  require Logger

  def create_document!(collection_name, document) do
    req = build_request("/collections/#{collection_name}/documents")
    {:ok, res} = Req.post(req, json: document)

    handle_response(res)
  end

  def search_documents!(collection_name, opts) do
    q = Keyword.get(opts, :q, "*")
    query_by = Keyword.get(opts, :query_by, "")
    filter_by = Keyword.get(opts, :filter_by, "")

    query_params = %{
      q: q,
      query_by: query_by,
      filter_by: filter_by,
      exclude_fields: "image_embedding"
    }

    req = build_request("/collections/#{collection_name}/documents/search")
    {:ok, res} = Req.get(req, params: query_params)
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

  def delete_document!(collection_name, document_id) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    {:ok, res} = Req.delete(req)

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

  defp handle_response(%Req.Response{status: status, body: body}) do
    case status do
      200 ->
        body

      201 ->
        body

      400 ->
        Logger.warning("Bad Request: #{inspect(body)}")
        raise "Bad Request"

      401 ->
        raise "Unauthorized"

      404 ->
        nil

      409 ->
        raise "Conflict"

      422 ->
        raise "Unprocessable Entity"

      503 ->
        raise "Service Unavailable"

      _ ->
        Logger.error("Unhandled status code #{status}: #{inspect(body)}")
        raise "Unknown error: #{status}"
    end
  end
end
