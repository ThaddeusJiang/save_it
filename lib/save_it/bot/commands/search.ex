defmodule SaveIt.Bot.Commands.Search do
  @moduledoc false

  alias SaveIt.Bot.MediaAnswer
  alias SaveIt.Bot.MediaUpload
  alias SaveIt.Bot.PhotoIndex
  alias SaveIt.Telegram

  def handle_photos(message, chat, photos) do
    MediaUpload.handle_photo(message, chat, "/search", photos)
  end

  def handle_missing_query(chat) do
    Telegram.send_message(
      chat.id,
      "What do you want to search? animal, food, etc. Or upload a photo with /search."
    )
  end

  def handle_query(chat, text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        Telegram.send_message(chat.id, "What do you want to search? animal, food, etc.")

      q ->
        photos = PhotoIndex.search_photos(q, belongs_to_id: chat.id)
        MediaAnswer.answer_photos(chat.id, photos)
    end
  end
end
