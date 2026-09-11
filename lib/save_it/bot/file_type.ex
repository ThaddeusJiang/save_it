defmodule SaveIt.Bot.FileType do
  @moduledoc false

  alias SaveIt.DownloadedFile

  @image_extensions [".png", ".jpg", ".jpeg", ".webp"]
  @video_extensions [".mp4", ".webm", ".mov", ".m4v", ".mkv"]
  @url_download_media_extensions @image_extensions ++ @video_extensions ++ [".gif"]

  def extension(file_name), do: Path.extname(file_name)

  def image?(file_name), do: extension(file_name) in @image_extensions

  def url_download_media?(file_name), do: extension(file_name) in @url_download_media_extensions

  def all_images?(files) when is_list(files) do
    Enum.all?(files, fn
      %DownloadedFile{file_name: file_name} ->
        image?(file_name)

      {file_name, _file_content, _source_url} ->
        image?(file_name)

      {file_name, _file_content} ->
        image?(file_name)

      file_name when is_binary(file_name) ->
        image?(file_name)
    end)
  end

  def media_type(file_name) do
    case extension(file_name) do
      ext when ext in @video_extensions -> "video"
      ".gif" -> "gif"
      ext when ext in @image_extensions -> "photo"
      _extension -> "file"
    end
  end
end
