defmodule SaveIt.Bot.MediaUpload do
  @moduledoc false

  require Logger

  alias SaveIt.Bot.MediaAnswer
  alias SaveIt.Bot.MessageInfo
  alias SaveIt.Bot.PhotoIndex
  alias SaveIt.Bot.TextHelper
  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive
  alias SmallSdk.Telegram, as: TelegramClient

  def handle_photo(message, chat, caption, photos) do
    photo = List.last(photos)
    file = ExGram.get_file!(photo.file_id)
    file_content = TelegramClient.download_file_content!(file.file_path)
    file_name = MessageInfo.telegram_file_name(file, photo.file_id, ".jpg")

    FileHelper.write_file(file_name, file_content, telegram_cache_key("photo", file.file_id))
    GoogleDrive.upload_file_content(chat.id, file_content, file_name)

    %{
      image: Base.encode64(file_content),
      caption: TextHelper.searchable_caption(caption),
      file_id: file.file_id,
      media_type: "photo",
      belongs_to_id: chat.id
    }
    |> Map.merge(MessageInfo.source_message_fields(chat, message))
    |> PhotoIndex.create_photo()
    |> answer_similar_media(chat.id, caption)
  end

  def handle_video(message, chat, caption, video) do
    typesense_photo =
      video
      |> media_thumbnail()
      |> create_media_thumbnail_index(chat, message, caption, video.file_id, "video")

    store_video_file(chat.id, video)
    answer_similar_media(typesense_photo, chat.id, caption)
  end

  def handle_animation(message, chat, caption, animation) do
    typesense_photo =
      animation
      |> media_thumbnail()
      |> create_media_thumbnail_index(chat, message, caption, animation.file_id, "gif")

    store_video_file(chat.id, animation)
    answer_similar_media(typesense_photo, chat.id, caption)
  end

  defp create_media_thumbnail_index(nil, _chat, _message, _caption, _file_id, _media_type),
    do: nil

  defp create_media_thumbnail_index(thumbnail, chat, message, caption, file_id, media_type) do
    thumbnail_file = ExGram.get_file!(thumbnail.file_id)
    thumbnail_content = TelegramClient.download_file_content!(thumbnail_file.file_path)

    %{
      image: Base.encode64(thumbnail_content),
      caption: TextHelper.searchable_caption(caption),
      file_id: file_id,
      media_type: media_type,
      belongs_to_id: chat.id
    }
    |> Map.merge(MessageInfo.source_message_fields(chat, message))
    |> PhotoIndex.create_photo()
  end

  defp store_video_file(chat_id, video) do
    case ExGram.get_file(video.file_id) do
      {:ok, file} ->
        store_video_file_content(chat_id, video, file)

      {:error, reason} ->
        handle_video_file_error(reason)
    end
  end

  defp store_video_file_content(chat_id, video, file) do
    case TelegramClient.download_file_content(file.file_path) do
      {:ok, file_content} ->
        file_name =
          Map.get(video, :file_name) ||
            MessageInfo.telegram_file_name(file, video.file_id, ".mp4")

        FileHelper.write_file(file_name, file_content, telegram_cache_key("video", video.file_id))
        upload_to_google_drive_if_configured(chat_id, file_content, file_name)
        :ok

      {:error, reason} ->
        handle_video_file_error(reason)
    end
  end

  defp handle_video_file_error(_reason) do
    Logger.warning("Skipping local backup for Telegram video")
    :error
  end

  defp upload_to_google_drive_if_configured(chat_id, file_content, file_name) do
    if GoogleDrive.configured?(chat_id) do
      GoogleDrive.upload_file_content(chat_id, file_content, file_name)
    else
      :ok
    end
  end

  defp media_thumbnail(media) do
    Map.get(media, :thumbnail) || Map.get(media, :thumb)
  end

  defp telegram_cache_key(media_type, file_id) do
    "telegram:#{media_type}:#{file_id}"
  end

  defp answer_similar_media(nil, _chat_id, _caption), do: :ok

  defp answer_similar_media(typesense_photo, chat_id, caption) do
    similar_photos =
      typesense_photo["id"]
      |> PhotoIndex.search_similar_photos(
        distance_threshold: similar_search_distance_threshold(caption),
        belongs_to_id: chat_id
      )
      |> exclude_uploaded_media(typesense_photo)

    if TextHelper.search_command_caption?(caption) do
      MediaAnswer.answer_similar_photos(chat_id, similar_photos)
    else
      MediaAnswer.answer_similar_photos_if_any(chat_id, similar_photos)
    end
  end

  defp similar_search_distance_threshold(caption) do
    if TextHelper.search_command_caption?(caption), do: 0.4, else: 0.1
  end

  defp exclude_uploaded_media(photos, uploaded_media) when is_list(photos) do
    uploaded_file_id = Map.get(uploaded_media, "file_id")
    uploaded_id = Map.get(uploaded_media, "id")

    Enum.reject(photos, fn photo ->
      same_present_value?(Map.get(photo, "file_id"), uploaded_file_id) or
        same_present_value?(Map.get(photo, "id"), uploaded_id)
    end)
  end

  defp same_present_value?(left, right) when is_binary(left) and is_binary(right) do
    left != "" and left == right
  end

  defp same_present_value?(_left, _right), do: false
end
