defmodule SaveIt.PhotoService do
  @moduledoc false

  require Logger
  alias SmallSdk.Typesense

  import SaveIt.SmallHelper.UrlHelper, only: [normalize_optional_url: 1, validate_url!: 1]

  def create_photo!(
        %{
          belongs_to_id: belongs_to_id
        } = photo_params
      ) do
    photo_create_input =
      photo_params
      |> normalize_photo_urls()
      |> Map.put_new(:media_type, "photo")
      |> Map.put(:belongs_to_id, Integer.to_string(belongs_to_id))
      |> Map.put(:inserted_at, DateTime.utc_now() |> DateTime.to_unix())

    Typesense.create_document!(
      "photos",
      photo_create_input
    )
  end

  def update_photo(photo) do
    Typesense.update_document!("photos", photo["id"], photo)
  end

  def update_photo_caption!(file_id, belongs_to_id, caption) do
    case get_photo(file_id, belongs_to_id) do
      photo when is_map(photo) ->
        photo
        |> Map.put("caption", caption)
        |> update_photo()

      nil ->
        raise "Photo not found for file_id #{file_id} and belongs_to_id #{belongs_to_id}"
    end
  end

  def delete_photo(file_id) do
    Typesense.delete_document_by_query("photos", "file_id:[#{file_id}]")
  end

  def delete_photos(file_ids) do
    Typesense.delete_document_by_query("photos", "file_id:[#{Enum.join(file_ids, ",")}]")
  end

  def get_photo(photo_id) do
    Typesense.get_document("photos", photo_id)
  end

  def get_photo(file_id, belongs_to_id) do
    case Typesense.search_documents!("photos",
           q: "*",
           filter_by: "file_id:=#{file_id} && belongs_to_id:=#{belongs_to_id}"
         ) do
      [photo | _] -> photo
      [] -> nil
    end
  end

  def search_photos!(q, opts) do
    belongs_to_id = Keyword.get(opts, :belongs_to_id)

    req_body = %{
      "searches" => [
        %{
          "query_by" => "caption",
          "q" => q,
          "collection" => "photos",
          "prefix" => true,
          "drop_tokens_threshold" => 0,
          "filter_by" => "belongs_to_id:=#{belongs_to_id}",
          "exclude_fields" => "image_embedding"
        },
        %{
          "query_by" => "image_embedding",
          "q" => q,
          "collection" => "photos",
          "prefix" => false,
          "vector_query" => "image_embedding:([], k: 20, distance_threshold: 0.785)",
          "drop_tokens_threshold" => 0,
          "filter_by" => "belongs_to_id:=#{belongs_to_id}",
          "exclude_fields" => "image_embedding"
        }
      ]
    }

    req = build_request("/multi_search")
    res = Req.post(req, json: req_body)
    data = Typesense.handle_response(res)
    log_search_response("search_photos", %{q: q, belongs_to_id: belongs_to_id}, data)

    data
    |> Map.get("results", [])
    |> prioritized_hits()
    |> Enum.map(&Map.get(&1, "document"))
    |> Enum.reject(&is_nil/1)
    |> unique_photos()
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
    res = Req.post(req, json: req_body)
    data = Typesense.handle_response(res)

    log_search_response(
      "search_similar_photos",
      %{photo_id: photo_id, belongs_to_id: belongs_to_id},
      data
    )

    results = data["results"]

    if results != [] do
      results
      |> hd()
      |> Map.get("hits")
      |> Enum.map(&Map.get(&1, "document"))
    else
      []
    end
  end

  defp get_env do
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

  defp log_search_response(action, metadata, data) do
    results = Map.get(data, "results", [])
    hits = Enum.flat_map(results, &Map.get(&1, "hits", []))

    hits_count =
      length(hits)

    top_vector_distances =
      hits
      |> Enum.take(5)
      |> Enum.map(&Map.get(&1, "vector_distance"))

    Logger.info(
      "Typesense #{action} response: " <>
        "metadata=#{format_log_fields(metadata)} " <>
        "hits_count=#{hits_count} " <>
        "top_vector_distances=#{format_log_list(top_vector_distances)} " <>
        "results_count=#{length(results)}"
    )
  end

  defp format_log_fields(fields) do
    Enum.map_join(fields, " ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
  end

  defp format_log_list(values) do
    values
    |> Enum.map_join(", ", &inspect/1)
    |> then(&"[#{&1}]")
  end

  defp prioritized_hits(results) do
    Enum.find_value(results, [], fn result ->
      case Map.get(result, "hits", []) do
        [] -> nil
        hits -> hits
      end
    end)
  end

  defp unique_photos(photos) do
    photos
    |> Enum.reduce({[], MapSet.new()}, fn photo, {acc, seen_keys} ->
      key = photo_key(photo)

      if is_nil(key) or MapSet.member?(seen_keys, key) do
        {acc, seen_keys}
      else
        {[photo | acc], MapSet.put(seen_keys, key)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp photo_key(photo) do
    Map.get(photo, "id") || Map.get(photo, "file_id")
  end

  defp normalize_photo_urls(photo_params) do
    Enum.reduce([:url, :download_url], photo_params, &normalize_photo_url_field/2)
  end

  defp normalize_photo_url_field(field, acc) do
    case Map.fetch(acc, field) do
      {:ok, url} -> put_normalized_photo_url(acc, field, normalize_optional_url(url))
      :error -> acc
    end
  end

  defp put_normalized_photo_url(acc, field, nil), do: Map.delete(acc, field)

  defp put_normalized_photo_url(acc, field, normalized_url),
    do: Map.put(acc, field, normalized_url)
end
