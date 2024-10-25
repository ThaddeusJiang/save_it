defmodule SaveIt.NoteService do
  require Logger

  alias SmallSdk.Typesense

  def create_note!(%{
        content: content,
        file_id: file_id,
        belongs_to_id: belongs_to_id
      }) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    note_create_input =
      %{
        content: content,
        file_id: file_id
      }
      |> Map.put(:belongs_to_id, Integer.to_string(belongs_to_id))
      |> Map.put(:inserted_at, now_unix)
      |> Map.put(:updated_at, now_unix)

    doc =
      Typesense.create_document!(
        "notes",
        note_create_input
      )

    Logger.debug("doc: #{inspect(doc)}")
    doc
  end
end
