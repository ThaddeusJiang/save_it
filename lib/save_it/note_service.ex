defmodule SaveIt.NoteService do
  require Logger

  alias SmallSdk.Typesense

  def create_note!(
        %{
          message_id: message_id,
          belongs_to_id: belongs_to_id
        } = note_params
      ) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    note_create_input =
      note_params
      |> Map.put(:message_id, Integer.to_string(message_id))
      |> Map.put(:belongs_to_id, Integer.to_string(belongs_to_id))
      |> Map.put(:inserted_at, now_unix)
      |> Map.put(:updated_at, now_unix)

    Typesense.create_document!(
      "notes",
      note_create_input
    )
  end

  def update_note!(id, %{} = note_params) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    note_update_input =
      note_params
      |> Map.put(:updated_at, now_unix)

    Typesense.update_document!(
      "notes",
      id,
      note_update_input
    )
  end

  def get_note!(message_id, chat_id) do
    docs =
      Typesense.search_documents!(
        "notes",
        q: "*",
        query_by: "content",
        filter_by: "message_id:=#{message_id} && belongs_to_id:=#{chat_id}"
      )

    case docs do
      nil ->
        nil

      [] ->
        nil

      [doc | rest] ->
        Logger.warning("Found multiple notes, skipping the rest: #{inspect(rest)}")

        doc
    end
  end
end
