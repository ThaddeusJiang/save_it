defmodule SaveIt.Migration.Typesense do
  alias SmallSdk.Typesense

  import SaveIt.SmallHelper.UrlHelper, only: [validate_url!: 1]

  alias Req.TransportError
  alias SaveIt.Migration.Typesense.Photo

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

  def migrate! do
    typesense_url = Application.fetch_env!(:save_it, :typesense_url)

    try do
      ensure_photos_collection!()
      migrate_photos_if_needed!()

      IO.puts("Typesense migration done")
    rescue
      error in TransportError ->
        raise """
        Typesense request failed: #{Exception.message(error)}
        Current TYPESENSE_URL: #{typesense_url}

        If you are using docker-compose locally, try:
          export TYPESENSE_URL=http://localhost:8108
          docker compose up -d typesense
          mix ts.migrate

        If you are running a release container, use:
          /app/bin/save_it eval 'SaveIt.Release.ts_migrate()'
        """
    end
  end

  def delete_collection(collection_name) do
    req = build_request("/collections/#{collection_name}")
    res = Req.delete(req)

    Typesense.handle_response(res)
  end

  defp ensure_photos_collection! do
    case photos_collection() do
      nil ->
        IO.puts("creating photos collection")
        Photo.create_photos_20241024!()

      _collection ->
        IO.puts("photos collection already exists, skipping create")
    end
  end

  defp migrate_photos_if_needed! do
    case photos_collection() do
      nil ->
        :ok

      collection ->
        if has_field?(collection, "url") do
          IO.puts("applying photos migration 20241029")
          Photo.migrate_photos_20241029!()
        else
          IO.puts("photos migration already applied, skipping")
        end
    end
  end

  defp photos_collection do
    list_collections!()
    |> Enum.find(fn collection -> collection["name"] == "photos" end)
  end

  defp has_field?(collection, field_name) do
    collection
    |> Map.get("fields", [])
    |> Enum.any?(fn field -> field["name"] == field_name end)
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
