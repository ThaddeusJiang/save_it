defmodule SaveIt.Bot.ThumbnailDownload do
  @moduledoc false

  import SaveIt.Bot.MapHelper, only: [map_get: 2]

  alias SaveIt.Bot.MessageInfo
  alias SaveIt.DownloadedFile
  alias SmallSdk.LinkPreview
  alias SmallSdk.Telegram, as: TelegramClient
  alias SmallSdk.WebDownloader

  def from_message(message) do
    with thumbnail when not is_nil(thumbnail) <- MessageInfo.thumbnail(message),
         file_id when is_binary(file_id) <- map_get(thumbnail, :file_id),
         {:ok, file} <- ExGram.get_file(file_id),
         {:ok, file_content} <- TelegramClient.download_file_content(file.file_path) do
      {:ok,
       %DownloadedFile{
         file_name: MessageInfo.telegram_file_name(file, file_id, ".jpg"),
         file_content: file_content
       }}
    else
      nil -> {:error, :no_thumbnail}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :missing_thumbnail_file_id}
    end
  end

  def preview_image(thumbnail_url, _source_url) when is_binary(thumbnail_url) do
    WebDownloader.download_file(thumbnail_url)
  end

  def preview_image(_thumbnail_url, source_url), do: LinkPreview.download_image(source_url)
end
