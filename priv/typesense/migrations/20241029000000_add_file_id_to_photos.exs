defmodule SaveIt.Typesense.Migrations.AddFileIdToPhotos20241029000000 do
  @moduledoc false

  require Logger

  alias SmallSdk.TypesenseMigration

  @collection_name "photos"

  def version, do: "20241029000000"
  def name, do: "add_file_id_to_photos"

  def up do
    unless TypesenseMigration.has_field?(@collection_name, "file_id") do
      TypesenseMigration.update_collection!(@collection_name, %{
        "fields" => [
          %{"name" => "file_id", "type" => "string", "optional" => true}
        ]
      })
    end

    backfill_file_id_from_url!()
  end

  def down do
    if TypesenseMigration.has_field?(@collection_name, "file_id") do
      TypesenseMigration.update_collection!(@collection_name, %{
        "fields" => [
          %{"name" => "file_id", "drop" => true}
        ]
      })
    end
  end

  def applied? do
    TypesenseMigration.has_field?(@collection_name, "file_id") and not backfill_needed?()
  end

  defp backfill_file_id_from_url! do
    Logger.info("Backfilling Typesense photos.file_id from url")

    if TypesenseMigration.has_field?(@collection_name, "url") do
      @collection_name
      |> TypesenseMigration.list_documents(per_page: 200, query_by: "url")
      |> Enum.each(fn doc ->
        case {Map.get(doc, "file_id"), Map.get(doc, "url")} do
          {nil, url} when is_binary(url) and url != "" ->
            file_id =
              url
              |> String.split("/")
              |> List.last()

            TypesenseMigration.update_document!(@collection_name, doc["id"], %{
              "file_id" => file_id
            })

          _ ->
            :ok
        end
      end)
    end
  end

  defp backfill_needed? do
    if TypesenseMigration.has_field?(@collection_name, "url") do
      @collection_name
      |> TypesenseMigration.list_documents(per_page: 200, query_by: "url")
      |> Enum.any?(fn doc ->
        is_nil(Map.get(doc, "file_id")) and is_binary(Map.get(doc, "url"))
      end)
    else
      false
    end
  end
end
