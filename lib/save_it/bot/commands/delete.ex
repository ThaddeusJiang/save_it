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
    case reply_to_message do
      %{photo: nil} ->
        Telegram.delete_message(chat_id, reply_to_message.message_id)

      %{photo: photo} ->
        photo
        |> Enum.map(& &1.file_id)
        |> PhotoService.delete_photos()

        Telegram.delete_message(chat_id, reply_to_message.message_id)

      _ ->
        Telegram.send_message(chat_id, @usage_message)
    end

    Telegram.delete_message(chat_id, message_id)
  end
end
