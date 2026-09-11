defmodule SaveIt.Bot.Commands.Delete do
  @moduledoc false

  alias SaveIt.PhotoService
  alias SaveIt.Telegram

  @usage_message "reply a message with /delete command."

  def handle_missing_reply(chat) do
    Telegram.send_message(chat.id, @usage_message)
  end

  def handle(chat, message_id, from, reply_to_message) do
    {:ok, %{id: bot_id, username: bot_username}} = ExGram.get_me()

    if Enum.member?([bot_id, from.id], reply_to_message.from.id) do
      delete(chat.id, message_id, reply_to_message)
    else
      Telegram.send_message(chat.id, "Only delete messages from @#{bot_username} and yourself.")
    end
  end

  defp delete(chat_id, message_id, reply_to_message) do
    reply_to_message
    |> indexed_file_ids()
    |> delete_indexed_media()

    Telegram.delete_message(chat_id, reply_to_message.message_id)
    Telegram.delete_message(chat_id, message_id)
  end

  defp delete_indexed_media([]), do: :ok
  defp delete_indexed_media(file_ids), do: PhotoService.delete_photos(file_ids)

  defp indexed_file_ids(message) do
    photo_file_ids(message) ++ media_file_ids(message)
  end

  defp photo_file_ids(%{photo: photos}) when is_list(photos) do
    Enum.flat_map(photos, fn photo ->
      case Map.get(photo, :file_id) || Map.get(photo, "file_id") do
        file_id when is_binary(file_id) and file_id != "" -> [file_id]
        _ -> []
      end
    end)
  end

  defp photo_file_ids(_message), do: []

  defp media_file_ids(message) do
    Enum.flat_map([:video, :animation], fn key ->
      case get_in(message, [key, :file_id]) || get_in(message, [key, "file_id"]) do
        file_id when is_binary(file_id) and file_id != "" -> [file_id]
        _ -> []
      end
    end)
  end
end
