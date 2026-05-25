defmodule SaveIt.Typesense.Migrations.AddDownloadUrlToPhotos20260525000000 do
  @moduledoc false

  alias SaveIt.TypesenseMigration
  alias SmallSdk.Typesense

  @collection_name "photos"

  def version, do: "20260525000000"
  def name, do: "add_download_url_to_photos"

  def up do
    case TypesenseMigration.field(@collection_name, "download_url") do
      nil ->
        Typesense.update_collection!(@collection_name, %{
          "fields" => [
            %{"name" => "download_url", "type" => "string", "optional" => true}
          ]
        })

      %{"optional" => true} ->
        :ok

      _field ->
        Typesense.update_collection!(@collection_name, %{
          "fields" => [
            %{"name" => "download_url", "drop" => true}
          ]
        })

        Typesense.update_collection!(@collection_name, %{
          "fields" => [
            %{"name" => "download_url", "type" => "string", "optional" => true}
          ]
        })
    end
  end

  def down do
    if TypesenseMigration.has_field?(@collection_name, "download_url") do
      Typesense.update_collection!(@collection_name, %{
        "fields" => [
          %{"name" => "download_url", "drop" => true}
        ]
      })
    end
  end

  def applied? do
    case TypesenseMigration.field(@collection_name, "download_url") do
      %{"optional" => true} -> true
      _ -> false
    end
  end
end
