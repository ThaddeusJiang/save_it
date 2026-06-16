defmodule SaveIt.Typesense.Migrations.AddUrlMetadataToPhotos20260616000000 do
  @moduledoc false

  alias SmallSdk.TypesenseMigration

  @collection_name "photos"
  @fields [
    %{"name" => "title", "type" => "string", "optional" => true},
    %{"name" => "description", "type" => "string", "optional" => true},
    %{"name" => "keywords", "type" => "string[]", "optional" => true}
  ]

  def version, do: "20260616000000"
  def name, do: "add_url_metadata_to_photos"

  def up do
    fields_to_add =
      Enum.reject(@fields, fn field ->
        optional_field?(field["name"])
      end)

    if fields_to_add != [] do
      TypesenseMigration.update_collection!(@collection_name, %{"fields" => fields_to_add})
    end
  end

  def down do
    fields_to_drop =
      @fields
      |> Enum.map(&%{"name" => &1["name"], "drop" => true})
      |> Enum.filter(fn field ->
        TypesenseMigration.has_field?(@collection_name, field["name"])
      end)

    if fields_to_drop != [] do
      TypesenseMigration.update_collection!(@collection_name, %{"fields" => fields_to_drop})
    end
  end

  def applied? do
    Enum.all?(@fields, &optional_field?(&1["name"]))
  end

  defp optional_field?(field_name) do
    case TypesenseMigration.field(@collection_name, field_name) do
      %{"optional" => true} -> true
      _field -> false
    end
  end
end
