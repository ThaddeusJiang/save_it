defmodule SmallSdk.WebDownloader do
  require Logger

  # FIXME:TODAY return {:ok, file_name, file_content} | {:error, reason}
  def download_files(urls) do
    Logger.info("download_files started, urls: #{inspect(urls)}")

    res =
      urls
      |> Enum.map(&download_file/1)
      |> Enum.reduce_while([], fn
        {:ok, filename, file_content}, acc -> {:cont, [{filename, file_content} | acc]}
        {:error, reason}, _ -> {:halt, {:error, reason}}
      end)

    {:ok, res}
  end

  # TODO: have to handle Stream data
  def download_file(url) do
    Logger.info("download_file started, url: #{url}")

    case Req.get(url) do
      {:ok, %{status: status, body: ""}} ->
        Logger.warning("Downloaded an empty file, status: #{status}")
        {:error, "💔 Downloaded an empty file"}

      {:ok, %{status: status, body: body, headers: headers}} ->
        case status do
          status when status in 200..209 ->
            filename =
              cond do
                String.contains?(url, "/tunnel") ->
                  parse_filename(url, :content_disposition, headers)

                true ->
                  parse_filename(url, :content_type, headers)
              end

            {:ok, filename, body}

          _ ->
            Logger.error("download_file failed, status: #{status}, body: #{inspect(body)}")
            {:error, "💔 Failed to download file"}
        end

      {:error, reason} ->
        Logger.error("download_file failed, reason: #{inspect(reason)}")
        {:error, "💔 Failed to download file"}
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
