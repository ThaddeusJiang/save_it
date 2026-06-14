defmodule SmallSdk.WebDownloader do
  @moduledoc false

  require Logger

  alias SaveIt.DownloadedFile

  def download_files(urls) do
    res =
      urls
      |> Enum.map(&download_file/1)
      |> Enum.reduce_while([], fn
        {:ok, %DownloadedFile{} = file}, acc ->
          {:cont, [file | acc]}

        {:error, reason}, _ ->
          {:halt, {:error, reason}}
      end)

    case res do
      {:error, reason} -> {:error, reason}
      files -> {:ok, files}
    end
  end

  # Stream responses are not supported yet.
  def download_file(url) do
    Logger.info("download_file started, url: #{url}")

    case Req.get(url) do
      {:ok, %{status: status, body: ""}} ->
        Logger.warning("Downloaded an empty file, status: #{status}")
        {:error, "💔 Downloaded an empty file"}

      {:ok, %{status: status, body: body, headers: headers}} when status in 200..209 ->
        filename = parse_filename_for_url(url, headers)
        Logger.notice("download_file succeeded, url: #{url}")

        {:ok,
         %DownloadedFile{
           file_name: filename,
           file_content: body,
           download_url: url
         }}

      {:ok, %{status: status, body: _body}} ->
        Logger.error("download_file failed", status: status)
        {:error, "💔 Failed to download file"}

      {:error, _reason} ->
        Logger.error("download_file failed")
        {:error, "💔 Failed to download file"}
    end
  end

  defp parse_filename_for_url(url, headers) do
    if String.contains?(url, "/tunnel") do
      parse_filename(url, :content_disposition, headers)
    else
      parse_filename(url, :content_type, headers)
    end
  end

  defp parse_filename(url, :content_type, headers) do
    ext =
      headers
      |> Map.get("content-type")
      |> List.first()
      |> String.split("/")
      |> List.last()

    gen_file_name(url) <> "." <> ext
  end

  defp parse_filename(_url, :content_disposition, headers) do
    filename =
      headers
      |> Map.get("content-disposition")
      |> List.first()
      |> String.split(";")
      |> Enum.find(fn x -> String.contains?(x, "filename") end)
      |> String.split("=")
      |> List.last()
      |> String.trim()
      |> String.replace("\"", "")

    filename
  end

  defp gen_file_name(url) do
    :crypto.hash(:sha256, url) |> Base.url_encode64(padding: false)
  end
end
