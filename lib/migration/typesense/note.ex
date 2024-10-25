defmodule Migration.Typesense.Note do
  alias Migration.Typesense

  @notes_schema %{
    "name" => "notes",
    "fields" => [
      # TODO: 第一步先实现文本，今后再考虑图片
      %{"name" => "content", "type" => "string"},
      # references photos.id
      # note: 抉择：这个 app 核心是给予图片的视觉笔记，暂时不考虑单独 text 的笔记
      # %{"name" => "photo_id", "type" => "string"},
      # note: 既然不能实现 RDB reference，那么就直接存储 file_id
      %{"name" => "message_id", "type" => "string"},
      %{"name" => "file_id", "type" => "string"},
      %{"name" => "belongs_to_id", "type" => "string"},
      %{"name" => "inserted_at", "type" => "int64"},
      %{"name" => "updated_at", "type" => "int64"}
    ],
    "default_sorting_field" => "inserted_at"
  }

  def create_collection!() do
    Typesense.create_collection!(@notes_schema)
  end

  def reset!() do
    Typesense.delete_collection!(@notes_schema["name"])
    Typesense.create_collection!(@notes_schema)
  end
end
