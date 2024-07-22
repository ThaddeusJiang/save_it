defmodule AierBot.FileHelper do
  require Logger
  use Tesla

  def download(url) do
    cond do
      String.contains?(url, "/api/stream") -> download_stream(url)
      true -> download_file(url)
    end
  end

  defp download_stream(url) do
    Logger.info("download_stream started", url: url)

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        file_name = gen_desc_filename() <> ".mp4"
        {:ok, file_name, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Status: #{status}"}

      {:error, reason} ->
        {:error, "Reason: #{inspect(reason)}"}
    end
  end

  defp download_file(url) do
    Logger.info("download_file started", url: url)

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body, headers: headers}} ->
        ext =
          headers
          |> Enum.find(fn {k, _} -> k == "content-type" end)
          |> elem(1)
          |> String.split("/")
          |> List.last()

        file_name = gen_desc_filename() <> "." <> ext
        {:ok, file_name, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Status: #{status}"}

      {:error, reason} ->
        {:error, "Reason #{inspect(reason)}"}
    end
  end

  def write_into_file(chat_id, file_name, file_content) do
    dir = Path.join(["./.local/storage", Integer.to_string(chat_id)])

    case File.mkdir_p(dir) do
      :ok ->
        case File.write(Path.join([dir, file_name]), file_content) do
          :ok ->
            Logger.info("File.write succeeded", file_name: file_name)

          {:error, reason} ->
            Logger.error("File.write failed, reason: #{reason}")
        end

      {:error, reason} ->
        Logger.error("File.mkdir_p failed, reason: #{reason}")
    end
  end

  # version 2: 2124-01-01 00:00:00 UTC is 4624022400
  # version 1: 10^16 - current_time, since JS max_safe_integer is 2^53 - 1 = 9007199254740991
  defp gen_desc_filename(datetime \\ DateTime.utc_now()) do
    last = ~U[2124-01-01 00:00:00Z] |> DateTime.to_unix()
    current = datetime |> DateTime.to_unix()

    (last - current)
    |> Integer.to_string()
    |> String.pad_leading(10, "0")
  end
end
