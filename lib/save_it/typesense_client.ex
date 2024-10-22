defmodule SaveIt.TypesenseClient do
  require Logger

  defp get_env() do
    url = Application.get_env(:save_it, :typesense_url)
    api_key = Application.get_env(:save_it, :typesense_api_key)

    {url, api_key}
  end

  def create_photo!(
        %{
          belongs_to_id: belongs_to_id
        } = photo_params
      ) do
    photo_create_input =
      photo_params
      |> Map.put(:belongs_to_id, Integer.to_string(belongs_to_id))
      |> Map.put(:inserted_at, DateTime.utc_now() |> DateTime.to_unix())

    create_document!(
      "photos",
      photo_create_input
    )
  end

  def update_photo(photo) do
    update_document("photos", photo)
  end

  def get_photo(photo_id) do
    get_document("photos", photo_id)
  end

  def search_photos!(q: q) do
    {url, api_key} = get_env()

    req =
      Req.new(
        base_url: url,
        url: "multi_search",
        headers: [{"X-TYPESENSE-API-KEY", api_key}, {"Content-Type", "application/json"}]
      )

    {:ok, res} =
      Req.post(req,
        json: %{
          "searches" => [
            %{
              "q" => q,
              "query_by" => "image_embedding",
              "collection" => "photos",
              "prefix" => false,
              "vector_query" => "image_embedding:([], k: 5, distance_threshold: 0.75)",
              "exclude_fields" => "image_embedding"
            }
          ]
        }
      )

    Logger.debug("debug: res #{inspect(res)}")

    res.body["results"] |> hd() |> Map.get("hits") |> Enum.map(&Map.get(&1, "document"))
  end

  def search_photos!(id, opts \\ []) do
    distance_threshold = Keyword.get(opts, :distance_threshold, 0.4)

    photos = search_similar_photos!(id, distance_threshold: distance_threshold)

    photos
  end

  def search_similar_photos!(photo_id, opts \\ []) when is_binary(photo_id) do
    {url, api_key} = get_env()

    distance_threshold = Keyword.get(opts, :distance_threshold, 0.4)

    req =
      Req.new(
        base_url: url,
        url: "/multi_search",
        headers: [{"X-TYPESENSE-API-KEY", api_key}, {"Content-Type", "application/json"}]
      )

    {:ok, res} =
      Req.post(req,
        json: %{
          "searches" => [
            %{
              "collection" => "photos",
              "q" => "*",
              "vector_query" =>
                "image_embedding:([], id:#{photo_id}, distance_threshold: #{distance_threshold}, k: 4)",
              "exclude_fields" => "image_embedding"
            }
          ]
        }
      )

    res.body["results"] |> hd() |> Map.get("hits") |> Enum.map(&Map.get(&1, "document"))
  end

  defp get_document(collection_name, document_id) do
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

  defp create_document!(collection_name, document) do
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

  defp update_document(collection_name, document) do
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
end
