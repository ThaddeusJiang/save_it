defmodule SmallSdk.Typesense do
  require Logger

  import Tj.UrlHelper, only: [validate_url!: 1]

  def create_document!(collection_name, document) do
    req = build_request("/collections/#{collection_name}/documents")
    res = Req.post(req, json: document)

    handle_response(res)
  end

  def list_documents(collection_name, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)
    req = build_request("/collections/#{collection_name}/documents/search")

    res =
      Req.get(req,
        params: %{
          q: "*",
          query_by: "caption",
          page: page,
          per_page: per_page
        }
      )

    data = handle_response(res)

    data["hits"] |> Enum.map(&Map.get(&1, "document"))
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
    res = Req.get(req, params: query_params)
    data = handle_response(res)

    data["hits"] |> Enum.map(&Map.get(&1, "document"))
  end

  def get_document(collection_name, document_id) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    res = Req.get(req)

    handle_response(res)
  end

  def update_document!(collection_name, document_id, update_input) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    res = Req.patch(req, json: update_input)

    handle_response(res)
  end

  def delete_document!(collection_name, document_id) do
    req = build_request("/collections/#{collection_name}/documents/#{document_id}")
    res = Req.delete(req)

    handle_response(res)
  end

  def create_search_key() do
    {url, _} = get_env()
    req = build_request("/keys")

    res =
      Req.post(req,
        json: %{
          "description" => "Search-only photos key",
          "actions" => ["documents:search"],
          "collections" => ["photos"]
        }
      )

    data = handle_response(res)

    %{
      url: url,
      api_key: data["value"]
    }
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

  def handle_response({:ok, %{status: status, body: body}}) do
    case status do
      status when status in 200..209 ->
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

  def handle_response({:error, reason}) do
    Logger.error("Request failed: #{inspect(reason)}")
    raise "Request failed"
  end

  def handle_response!(%{status: status, body: body}) do
    case status do
      status when status in 200..209 ->
        body

      status ->
        Logger.warning("Request failed with status #{status}: #{inspect(body)}")
        raise "Request failed with status #{status}"
    end
  end
end
