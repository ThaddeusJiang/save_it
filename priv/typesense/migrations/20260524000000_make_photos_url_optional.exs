defmodule SaveIt.Typesense.Migrations.MakePhotosUrlOptional20260524000000 do
  @moduledoc false

  alias SaveIt.TypesenseMigration
  alias SmallSdk.Typesense

  @collection_name "photos"

  def version, do: "20260524000000"
  def name, do: "make_photos_url_optional"

  def up do
    case TypesenseMigration.field(@collection_name, "url") do
      nil ->
        Typesense.update_collection!(@collection_name, %{
          "fields" => [
            %{"name" => "url", "type" => "string", "optional" => true}
          ]
        })

      %{"optional" => true} ->
        :ok

      _field ->
        Typesense.update_collection!(@collection_name, %{
          "fields" => [
            %{"name" => "url", "drop" => true}
          ]
        })

        Typesense.update_collection!(@collection_name, %{
          "fields" => [
            %{"name" => "url", "type" => "string", "optional" => true}
          ]
        })
    end
  end

  def down do
    if TypesenseMigration.has_field?(@collection_name, "url") do
      Typesense.update_collection!(@collection_name, %{
        "fields" => [
          %{"name" => "url", "drop" => true}
        ]
      })
    end
  end

  def applied? do
    case TypesenseMigration.field(@collection_name, "url") do
      %{"optional" => true} -> true
      _ -> false
    end
  end
end
