defmodule AierBot.FileHelper do
  require Logger
  use Tesla

  @files_dir "./.local/storage/files"
  @urls_dir "./.local/storage/urls"

  def download(url) do
    cond do
      String.contains?(url, "/api/stream") -> download_stream(url)
      true -> download_file(url)
    end
  end

  def download_files(urls) do
    Logger.info("download_files started, urls: #{inspect(urls)}")

    res =
      urls
      |> Enum.map(&download/1)
      |> Enum.reduce_while([], fn
        {:ok, file_name, file_content}, acc -> {:cont, [{file_name, file_content} | acc]}
        {:error, reason}, _ -> {:halt, {:error, reason}}
      end)

    {:ok, res}
  end

  defp download_stream(url) do
    Logger.info("download_stream started, url: #{url}")

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
    Logger.info("download_file started, url: #{url}")

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

  def write_file(file_name, file_content, download_url) do
    write_file_to_disk(@files_dir, file_name, file_content)

    hashed_url = :crypto.hash(:sha256, download_url) |> Base.url_encode64(padding: false)
    write_file_to_disk(@urls_dir, hashed_url, file_name)
  end

  def write_folder(original_url, files) do
    hashed_url = :crypto.hash(:sha256, original_url) |> Base.url_encode64(padding: false)

    Enum.each(files, fn {file_name, file_content} ->
      write_file_to_disk(Path.join(@files_dir, hashed_url), file_name, file_content)
    end)

    write_file_to_disk(@urls_dir, hashed_url, files |> Enum.map(&elem(&1, 0)) |> Enum.join("\n"))
  end

  defp write_file_to_disk(dir, file_name, file_content) do
    case File.mkdir_p(dir) do
      :ok ->
        case File.write(Path.join([dir, file_name]), file_content) do
          :ok ->
            Logger.info("File.write succeeded")

          {:error, reason} ->
            Logger.error("File.write failed, reason: #{reason}")
        end

      {:error, reason} ->
        Logger.error("File.mkdir_p failed, reason: #{reason}")
    end
  end

  def get_downloaded_file(download_url) do
    hashed_url = :crypto.hash(:sha256, download_url) |> Base.url_encode64(padding: false)

    case File.read(Path.join([@urls_dir, hashed_url])) do
      {:ok, file} -> Path.join([@files_dir, file |> String.trim()])
      {:error, _} -> nil
    end
  end

  def get_downloaded_files(download_url) do
    hashed_url = :crypto.hash(:sha256, download_url) |> Base.url_encode64(padding: false)

    case File.read(Path.join([@urls_dir, hashed_url])) do
      {:ok, file} ->
        file
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&Path.join([@files_dir, hashed_url, &1]))

      {:error, _} ->
        nil
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
