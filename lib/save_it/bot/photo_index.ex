defmodule SaveIt.Bot.PhotoIndex do
  @moduledoc false

  require Logger

  import SaveIt.Bot.MapHelper, only: [put_optional: 3]

  alias SaveIt.Bot.LogFormat
  alias SaveIt.PhotoService

  def url_metadata_opts(opts) do
    Keyword.take(opts, [:title, :description, :keywords])
  end

  def put_url_metadata_fields(map, opts) do
    map
    |> put_optional(:title, Keyword.get(opts, :title))
    |> put_optional(:description, Keyword.get(opts, :description))
    |> put_optional(:keywords, Keyword.get(opts, :keywords))
  end

  def index_photo(photo_params) do
    case create_photo(photo_params) do
      nil -> :error
      _photo -> :ok
    end
  end

  def create_photo(photo_params) do
    Logger.debug(
      "Typesense photo indexing started " <>
        "media_type=#{Map.get(photo_params, :media_type, "photo")} " <>
        "source_url=#{LogFormat.url(Map.get(photo_params, :url))} " <>
        "download_url=#{LogFormat.url(Map.get(photo_params, :download_url))}"
    )

    photo_params
    |> PhotoService.create_photo!()
    |> include_created_photo_metadata(photo_params)
  rescue
    error ->
      Logger.error("Typesense create_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, _reason ->
      Logger.error("Typesense create_photo failed", kind: kind)
      nil
  end

  def search_photos(q, opts) do
    PhotoService.search_photos!(q, opts)
  rescue
    error ->
      Logger.error("Typesense search_photos failed: #{Exception.message(error)}")
      []
  catch
    kind, _reason ->
      Logger.error("Typesense search_photos failed", kind: kind)
      []
  end

  def search_similar_photos(photo_id, opts) do
    PhotoService.search_similar_photos!(photo_id, opts)
  rescue
    error ->
      Logger.error("Typesense search_similar_photos failed: #{Exception.message(error)}")
      []
  catch
    kind, _reason ->
      Logger.error("Typesense search_similar_photos failed", kind: kind)
      []
  end

  def get_photo(file_id, belongs_to_id) do
    PhotoService.get_photo(file_id, belongs_to_id)
  rescue
    error ->
      Logger.error("Typesense get_photo failed: #{Exception.message(error)}")
      nil
  catch
    kind, _reason ->
      Logger.error("Typesense get_photo failed", kind: kind)
      nil
  end

  def get_photo_by_source_message_url(url, belongs_to_id) do
    PhotoService.get_photo_by_source_message_url(url, belongs_to_id)
  rescue
    error ->
      Logger.error(
        "Typesense get_photo_by_source_message_url failed: #{Exception.message(error)}"
      )

      nil
  catch
    kind, _reason ->
      Logger.error("Typesense get_photo_by_source_message_url failed", kind: kind)
      nil
  end

  defp include_created_photo_metadata(photo, photo_params) when is_map(photo) do
    Enum.reduce([:file_id, :media_type], photo, fn key, acc ->
      case Map.fetch(photo_params, key) do
        {:ok, value} -> Map.put_new(acc, Atom.to_string(key), value)
        :error -> acc
      end
    end)
  end

  defp include_created_photo_metadata(photo, _photo_params), do: photo
end
