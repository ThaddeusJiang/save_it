defmodule SaveIt.Typesense.Migrations.AddThumbnailUrlToPhotos20260614001000 do
  @moduledoc false

  alias SmallSdk.TypesenseMigration

  @collection_name "photos"
  @field %{"name" => "thumbnail_url", "type" => "string", "optional" => true}

  def version, do: "20260614001000"
  def name, do: "add_thumbnail_url_to_photos"

  def up do
    case TypesenseMigration.field(@collection_name, @field["name"]) do
      nil ->
        TypesenseMigration.update_collection!(@collection_name, %{"fields" => [@field]})

      %{"optional" => true} ->
        :ok

      _field ->
        TypesenseMigration.update_collection!(@collection_name, %{
          "fields" => [%{"name" => @field["name"], "drop" => true}]
        })

        TypesenseMigration.update_collection!(@collection_name, %{"fields" => [@field]})
    end
  end

  def down do
    if TypesenseMigration.has_field?(@collection_name, @field["name"]) do
      TypesenseMigration.update_collection!(@collection_name, %{
        "fields" => [%{"name" => @field["name"], "drop" => true}]
      })
    end
  end

  def applied? do
    case TypesenseMigration.field(@collection_name, @field["name"]) do
      %{"optional" => true} -> true
      _field -> false
    end
  end
end
