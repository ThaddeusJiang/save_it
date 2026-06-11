defmodule SaveIt.Typesense.Migrations.AddMediaTypeToPhotos20260611000000 do
  @moduledoc false

  alias SaveIt.TypesenseMigration
  alias SmallSdk.Typesense

  @collection_name "photos"

  def version, do: "20260611000000"
  def name, do: "add_media_type_to_photos"

  def up do
    unless TypesenseMigration.has_field?(@collection_name, "media_type") do
      Typesense.update_collection!(@collection_name, %{
        "fields" => [
          %{"name" => "media_type", "type" => "string", "optional" => true}
        ]
      })
    end
  end

  def down do
    if TypesenseMigration.has_field?(@collection_name, "media_type") do
      Typesense.update_collection!(@collection_name, %{
        "fields" => [
          %{"name" => "media_type", "drop" => true}
        ]
      })
    end
  end

  def applied? do
    TypesenseMigration.has_field?(@collection_name, "media_type")
  end
end
