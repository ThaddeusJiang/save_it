defmodule SaveIt.Typesense.Migrations.DropSourceMessageIdFromPhotos20260614000000 do
  @moduledoc false

  alias SmallSdk.TypesenseMigration

  @collection_name "photos"
  @field %{"name" => "source_message_id", "type" => "int64", "optional" => true}

  def version, do: "20260614000000"
  def name, do: "drop_source_message_id_from_photos"

  def up do
    if TypesenseMigration.has_field?(@collection_name, @field["name"]) do
      TypesenseMigration.update_collection!(@collection_name, %{
        "fields" => [%{"name" => @field["name"], "drop" => true}]
      })
    end
  end

  def down do
    unless TypesenseMigration.has_field?(@collection_name, @field["name"]) do
      TypesenseMigration.update_collection!(@collection_name, %{"fields" => [@field]})
    end
  end

  def applied? do
    not TypesenseMigration.has_field?(@collection_name, @field["name"])
  end
end
