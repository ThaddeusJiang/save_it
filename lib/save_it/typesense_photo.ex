defmodule SaveIt.TypesensePhoto do
  require Logger
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
    Typesense.update_document("photos", photo.id, photo)
  end

  def get_photo(photo_id) do
    Typesense.get_document("photos", photo_id)
  end

  def search_photos!(q, opts) do
    belongs_to_id = Keyword.get(opts, :belongs_to_id)

    req_body = %{
      "searches" => [
        %{
          "query_by" => "image_embedding,caption",
          "q" => q,
          "collection" => "photos",
          "prefix" => false,
          "vector_query" => "image_embedding:([], k: 5, distance_threshold: 0.75)",
          "filter_by" => "belongs_to_id:#{belongs_to_id}",
          "exclude_fields" => "image_embedding"
        }
      ]
    }

    req = build_request("/multi_search")
    {:ok, res} = Req.post(req, json: req_body)

    res.body["results"] |> typesense_results_to_documents()
  end

  def search_similar_photos!(photo_id, opts \\ []) when is_binary(photo_id) do
    belongs_to_id = Keyword.get(opts, :belongs_to_id)
    distance_threshold = Keyword.get(opts, :distance_threshold, 0.4)

    req_body = %{
      "searches" => [
        %{
          "collection" => "photos",
          "q" => "*",
          "vector_query" =>
            "image_embedding:([], id:#{photo_id}, distance_threshold: #{distance_threshold}, k: 4)",
          "filter_by" => "belongs_to_id:#{belongs_to_id}",
          "exclude_fields" => "image_embedding"
        }
      ]
    }

    req = build_request("/multi_search")
    {:ok, res} = Req.post(req, json: req_body)

    res.body["results"] |> typesense_results_to_documents()
  end

  defp typesense_results_to_documents(results) do
    results |> hd() |> Map.get("hits") |> Enum.map(&Map.get(&1, "document"))
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
