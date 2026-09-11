defmodule SaveIt.Bot.MessageInfo do
  @moduledoc false

  require Logger

  import SaveIt.Bot.MapHelper, only: [map_get: 2, map_value: 2, put_optional: 3]

  alias SaveIt.Bot.TextHelper

  def message_id(message) when is_map(message) do
    Map.get(message, :message_id) || Map.get(message, "message_id")
  end

  def message_thread_id(message) when is_map(message) do
    Map.get(message, :message_thread_id) || Map.get(message, "message_thread_id")
  end

  def user_text_caption(message) do
    (map_get(message, :text) || map_get(message, :caption))
    |> TextHelper.strip_urls()
  end

  def link_preview_url(message) do
    message
    |> map_get(:link_preview_options)
    |> map_get(:url)
  end

  def telegram_file_name(file, file_id, fallback_extension) do
    case Map.get(file, :file_path) do
      file_path when is_binary(file_path) and file_path != "" ->
        Path.basename(file_path)

      _ ->
        file_id <> fallback_extension
    end
  end

  def file_id(msg) do
    photos =
      cond do
        is_map(msg) and Map.has_key?(msg, :photo) -> msg.photo
        is_map(msg) and Map.has_key?(msg, "photo") -> msg["photo"]
        true -> nil
      end

    case photos do
      [_ | _] = photos ->
        photo = List.last(photos)
        Map.get(photo, :file_id) || Map.get(photo, "file_id")

      _ ->
        Logger.error("No photo found in the message")
        nil
    end
  end

  def video_file_id(msg) do
    msg
    |> map_get(:video)
    |> map_get(:file_id)
  end

  def animation_file_id(msg) do
    msg
    |> map_get(:animation)
    |> map_get(:file_id)
  end

  def thumbnail(nil), do: nil

  def thumbnail(message) do
    [
      largest_photo(map_get(message, :photo)),
      map_get(message, :thumbnail),
      map_get(message, :thumb),
      media_thumbnail(map_get(message, :animation)),
      media_thumbnail(map_get(message, :audio)),
      media_thumbnail(map_get(message, :document)),
      media_thumbnail(map_get(message, :video)),
      media_thumbnail(map_get(message, :video_note)),
      media_thumbnail(map_get(message, :sticker)),
      thumbnail(map_get(message, :external_reply))
    ]
    |> Enum.find(&thumbnail_file?/1)
  end

  def source_message_fields(chat, message) when is_map(message) do
    source_message_fields(chat, message_id(message), message_thread_id(message))
  end

  def source_message_fields(chat, message_id) when is_integer(message_id) do
    source_message_fields(chat, message_id, nil)
  end

  def source_message_fields(_chat, _message), do: %{}

  def source_message_fields(chat, message_id, message_thread_id) when is_integer(message_id) do
    %{}
    |> put_optional(
      :source_message_url,
      telegram_message_url(chat, message_id, message_thread_id)
    )
  end

  def source_message_fields(_chat, _message_id, _message_thread_id), do: %{}

  defp telegram_message_url(chat, message_id, message_thread_id) do
    chat_type = map_value(chat, :type)
    username = map_value(chat, :username)
    chat_id = map_value(chat, :id)
    private_channel_id = telegram_private_channel_id(chat_id)

    cond do
      chat_type == "private" ->
        private_chat_message_key(chat_id, message_id)

      is_binary(username) and username != "" ->
        "https://t.me/#{username}/#{message_id}"

      private_channel_id && is_integer(message_thread_id) ->
        "https://t.me/c/#{private_channel_id}/#{message_thread_id}/#{message_id}"

      private_channel_id ->
        "https://t.me/c/#{private_channel_id}/#{message_id}"

      true ->
        nil
    end
  end

  defp private_chat_message_key(chat_id, message_id) when not is_nil(chat_id) do
    "telegram:private:#{chat_id}/#{message_id}"
  end

  defp private_chat_message_key(_chat_id, _message_id), do: nil

  defp telegram_private_channel_id(chat_id) do
    chat_id = to_string(chat_id)

    if String.starts_with?(chat_id, "-100") do
      String.replace_prefix(chat_id, "-100", "")
    end
  end

  defp media_thumbnail(nil), do: nil

  defp media_thumbnail(media) do
    map_get(media, :thumbnail) || map_get(media, :thumb)
  end

  defp largest_photo([_ | _] = photos), do: List.last(photos)
  defp largest_photo(_photos), do: nil

  defp thumbnail_file?(thumbnail) do
    thumbnail
    |> map_get(:file_id)
    |> is_binary()
  end
end
