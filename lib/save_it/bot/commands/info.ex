defmodule SaveIt.Bot.Commands.Info do
  @moduledoc false

  alias SaveIt.Bot.MessageInfo
  alias SaveIt.Bot.PhotoIndex
  alias SaveIt.Bot.TextHelper
  alias SaveIt.Telegram

  @usage_message "reply a photo, video, or gif with /info command."

  def handle(chat, nil) do
    Telegram.send_message(chat.id, @usage_message)
  end

  def handle(chat, reply_to_message) do
    case media_file_id(reply_to_message) do
      file_id when is_binary(file_id) ->
        send_info(chat, reply_to_message, file_id)

      _ ->
        Telegram.send_message(chat.id, @usage_message)
    end
  end

  defp send_info(chat, reply_to_message, file_id) do
    case find_photo(chat, reply_to_message, file_id) do
      nil ->
        Telegram.send_message(chat.id, "Media info not found.")

      photo ->
        Telegram.send_message(chat.id, message(reply_to_message, photo))
    end
  end

  defp find_photo(chat, reply_to_message, file_id) do
    PhotoIndex.get_photo(file_id, chat.id) ||
      get_photo_by_source_message_url(chat, reply_to_message)
  end

  defp get_photo_by_source_message_url(chat, reply_to_message) do
    case Map.get(MessageInfo.source_message_fields(chat, reply_to_message), :source_message_url) do
      url when is_binary(url) and url != "" ->
        PhotoIndex.get_photo_by_source_message_url(url, chat.id)

      _ ->
        nil
    end
  end

  defp media_file_id(%{photo: [_ | _] = photos}) do
    photos |> List.last() |> Map.get(:file_id)
  end

  defp media_file_id(%{video: %{file_id: file_id}}), do: file_id
  defp media_file_id(%{animation: %{file_id: file_id}}), do: file_id
  defp media_file_id(_reply_to_message), do: nil

  defp message(reply_to_message, photo) do
    [
      line("Message URL", public_source_message_url(Map.get(photo, "source_message_url"))),
      line("Original URL", Map.get(photo, "url")),
      line("Caption", Map.get(photo, "caption")),
      line("Title", Map.get(photo, "title")),
      line("Description", Map.get(photo, "description")),
      line("Keywords", keywords(Map.get(photo, "keywords"))),
      line("Saved at", saved_at(photo, reply_to_message))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp public_source_message_url("https://t.me/" <> _ = url), do: url
  defp public_source_message_url(_url), do: nil

  defp line(_label, nil), do: nil
  defp line(_label, ""), do: nil
  defp line(label, value), do: "#{label}: #{value}"

  defp keywords([_ | _] = keywords), do: Enum.join(keywords, ", ")
  defp keywords(_keywords), do: nil

  defp saved_at(photo, reply_to_message) do
    TextHelper.format_unix_time(Map.get(photo, "inserted_at") || Map.get(reply_to_message, :date))
  end
end
