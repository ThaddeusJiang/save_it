defmodule SaveIt.Typesense.Migrations.AddSourceMessageToPhotos20260611001000 do
  @moduledoc false

  alias SaveIt.TypesenseMigration
  alias SmallSdk.Typesense

  @collection_name "photos"
  @fields [
    %{"name" => "source_message_id", "type" => "int64", "optional" => true},
    %{"name" => "source_message_url", "type" => "string", "optional" => true}
  ]

  def version, do: "20260611001000"
  def name, do: "add_source_message_to_photos"

  def up do
    fields_to_add =
      Enum.reject(@fields, fn %{"name" => name} ->
        TypesenseMigration.has_field?(@collection_name, name)
      end)

    if fields_to_add != [] do
      Typesense.update_collection!(@collection_name, %{"fields" => fields_to_add})
    end
  end

  def down do
    fields_to_drop =
      @fields
      |> Enum.map(&Map.fetch!(&1, "name"))
      |> Enum.filter(&TypesenseMigration.has_field?(@collection_name, &1))
      |> Enum.map(&%{"name" => &1, "drop" => true})

    if fields_to_drop != [] do
      Typesense.update_collection!(@collection_name, %{"fields" => fields_to_drop})
    end
  end

  def applied? do
    Enum.all?(@fields, fn %{"name" => name} ->
      TypesenseMigration.has_field?(@collection_name, name)
    end)
  end
end
