defmodule SaveIt.Bot.MediaAnswer do
  @moduledoc false

  require Logger

  alias SaveIt.Telegram

  @similar_photos_found_message "Similar photos found."

  def answer_photos(chat_id, []) do
    Telegram.send_message(chat_id, "No photos found.")
  end

  def answer_photos(chat_id, [photo]) do
    send_similar_media(chat_id, photo)
    :ok
  end

  def answer_photos(chat_id, similar_photos) do
    media = Enum.map(similar_photos, &saved_media_group_input/1)

    case ExGram.send_media_group(chat_id, media) do
      {:ok, _response} ->
        :ok

      {:error, _reason} ->
        Logger.warning(
          "Failed to send similar media group, falling back to individual media",
          kind: :telegram_media_group_failed
        )

        Enum.each(similar_photos, &send_similar_media(chat_id, &1))
        :ok
    end
  end

  def answer_similar_photos(chat_id, []) do
    answer_photos(chat_id, [])
  end

  def answer_similar_photos(chat_id, photos) when is_list(photos) do
    Telegram.send_message(chat_id, @similar_photos_found_message)
    answer_photos(chat_id, photos)
  end

  def answer_similar_photos_if_any(_chat_id, []), do: nil

  def answer_similar_photos_if_any(chat_id, photos) when is_list(photos),
    do: answer_similar_photos(chat_id, photos)

  defp send_similar_media(chat_id, media) do
    case send_saved_media(chat_id, media) do
      {:ok, _response} ->
        :ok

      {:error, _reason} ->
        Logger.warning(
          "Skipping unavailable similar media",
          file_id: media["file_id"]
        )

        :error
    end
  end

  defp send_saved_media(chat_id, %{"media_type" => "video"} = media) do
    ExGram.send_video(chat_id, media["file_id"],
      caption: media["caption"],
      supports_streaming: true
    )
  end

  defp send_saved_media(chat_id, %{"media_type" => "gif"} = media) do
    ExGram.send_animation(chat_id, media["file_id"], caption: media["caption"])
  end

  defp send_saved_media(chat_id, media) do
    ExGram.send_photo(chat_id, media["file_id"], caption: media["caption"])
  end

  defp saved_media_group_input(%{"media_type" => "video"} = media) do
    %ExGram.Model.InputMediaVideo{
      type: "video",
      media: media["file_id"],
      caption: media["caption"],
      supports_streaming: true
    }
  end

  defp saved_media_group_input(%{"media_type" => "gif"} = media) do
    %ExGram.Model.InputMediaAnimation{
      type: "animation",
      media: media["file_id"],
      caption: media["caption"]
    }
  end

  defp saved_media_group_input(media) do
    %ExGram.Model.InputMediaPhoto{
      type: "photo",
      media: media["file_id"],
      caption: media["caption"]
    }
  end
end
