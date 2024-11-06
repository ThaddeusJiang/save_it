defmodule SaveIt.FileHelper do
  require Logger

  @files_dir "./data/storage/files"
  @urls_dir "./data/storage/urls"

  def set_google_drive_folder_id(chat_id, folder_id) do
    write_file_to_disk("./data/settings/#{chat_id}", "folder_id.txt", folder_id)
  end

  def get_google_drive_folder_id(chat_id) do
    case File.read(Path.join(["./data/settings/#{chat_id}", "folder_id.txt"])) do
      {:ok, folder_id} -> folder_id
      {:error, _} -> nil
    end
  end

  def set_google_device_code(chat_id, device_code) do
    write_file_to_disk("./data/settings/#{chat_id}", "device_code.txt", device_code)
  end

  def get_google_device_code(chat_id) do
    case File.read(Path.join(["./data/settings/#{chat_id}", "device_code.txt"])) do
      {:ok, device_code} -> device_code
      {:error, _} -> nil
    end
  end

  def set_google_access_token(chat_id, access_token) do
    write_file_to_disk("./data/settings/#{chat_id}", "access_token.txt", access_token)
  end

  def get_google_access_token(chat_id) do
    case File.read(Path.join(["./data/settings/#{chat_id}", "access_token.txt"])) do
      {:ok, access_token} -> access_token
      {:error, _} -> nil
    end
  end

  @doc """
  - dir: ./data/settings/<chat_id>.txt TODO: erlang / elixir style

  settings = %{
    "device_code" => "value"
  }
  """
  def save_chat_settings(chat_id, settings) do
    write_file_to_disk("./data/settings", "#{chat_id}.txt", settings)
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
end
