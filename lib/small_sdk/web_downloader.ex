defmodule SmallSdk.WebDownloader do
  @moduledoc false

  require Logger

  alias SaveIt.DownloadedFile
  alias SaveIt.FilenameGenerator

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
    case Req.get(url) do
      {:ok, %{status: status, body: ""}} ->
        Logger.warning("Downloaded an empty file, status: #{status}")
        {:error, "💔 Downloaded an empty file"}

      {:ok, %{status: status, body: body, headers: headers}} when status in 200..209 ->
        filename = file_name_for_url(url, headers)

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

  defp file_name_for_url(url, headers) do
    original =
      if String.contains?(url, "/tunnel") do
        content_disposition_filename(headers) || url
      else
        url
      end

    FilenameGenerator.random(original, fallback_extension: content_type_extension(headers))
  end

  defp content_type_extension(headers) do
    headers
    |> header_first("content-type")
    |> case do
      nil ->
        nil

      content_type ->
        content_type
        |> String.split(";", parts: 2)
        |> List.first()
        |> String.trim()
        |> String.split("/")
        |> List.last()
    end
  end

  defp content_disposition_filename(headers) do
    headers
    |> header_first("content-disposition")
    |> case do
      nil ->
        nil

      content_disposition ->
        content_disposition
        |> String.split(";")
        |> Enum.find(fn x -> String.contains?(x, "filename") end)
        |> case do
          nil ->
            nil

          filename ->
            filename
            |> String.split("=", parts: 2)
            |> List.last()
            |> String.trim()
            |> String.replace("\"", "")
            |> Path.basename()
            |> blank_to_nil()
        end
    end
  end

  defp header_first(headers, name) do
    headers
    |> Map.get(name, [])
    |> List.first()
  end

  defp blank_to_nil(value) do
    if value == "", do: nil, else: value
  end
end
