defmodule SaveIt.PhotoService do
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
    Typesense.update_document!("photos", photo["id"], photo)
  end

  def update_photo_caption!(file_id, belongs_to_id, caption) do
    get_photo!(file_id, belongs_to_id)
    |> Map.put("caption", caption)
    |> update_photo()
  end

  def get_photo(photo_id) do
    Typesense.get_document("photos", photo_id)
  end

  def get_photo!(file_id, belongs_to_id) do
    case Typesense.search_documents!("photos",
           q: "*",
           query_by: "caption",
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
    data = handle_response(res)

    data["results"] |> hd() |> Map.get("hits") |> Enum.map(&Map.get(&1, "document"))
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
    data = handle_response(res)

    data["results"] |> hd() |> Map.get("hits") |> Enum.map(&Map.get(&1, "document"))
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

  defp handle_response(res) do
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
end
