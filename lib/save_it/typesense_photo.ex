defmodule SaveIt.TypesensePhoto do
  alias SmallSdk.Typesense

  def create_photo!(
        %{
          belongs_to_id: belongs_to_id
        } = photo_params
      ) do
    photo_create_input =
      photo_params
      |> Map.put(:belongs_to_id, Integer.to_string(belongs_to_id))
      |> Map.put(:inserted_at, DateTime.utc_now() |> DateTime.to_unix())

    Typesense.create_document!(
      "photos",
      photo_create_input
    )
  end

  def update_photo(photo) do
    Typesense.update_document("photos", photo)
  end

  def get_photo(photo_id) do
    Typesense.get_document("photos", photo_id)
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

    res.body["results"] |> hd() |> Map.get("hits") |> Enum.map(&Map.get(&1, "document"))
  end

  def search_photos!(id, opts \\ []) do
    distance_threshold = Keyword.get(opts, :distance_threshold, 0.4)

    search_similar_photos!(id, distance_threshold: distance_threshold)
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

  defp get_env() do
    url = Application.fetch_env!(:save_it, :typesense_url)
    api_key = Application.fetch_env!(:save_it, :typesense_api_key)

    {url, api_key}
  end
end
