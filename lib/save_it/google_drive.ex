defmodule SaveIt.GoogleDrive do
  @moduledoc """
  Google Drive integration used by the bot for optional uploads.

  Future improvements:
  - Skip uploads early when Drive is not configured.
  - Move the raw API client into `SmallSdk`.
  - Support browsing and selecting folders.
  """
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  require Logger
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://www.googleapis.com")

  plug(Tesla.Middleware.Headers, [
    {"Content-Type", "application/json"}
  ])

  plug(Tesla.Middleware.JSON)

  @upload_type "resumable"
  @chunk_size 8 * 1024 * 1024

  # Google Drive folder listing is limited and may not match the public guide exactly.
  def list_files(chat_id) do
    access_token = FileHelper.get_google_access_token(chat_id)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"}
    ]

    query_params = [
      mimeType: "application/vnd.google-apps.folder",
      fields: "files(id, name)"
    ]

    get("/drive/v3/files", query: query_params, headers: headers)
    |> handle_response()
  end

  def upload_file_content(chat_id, file_content, file_name) do
    # oauth = FileHelper.get_google_oauth(chat_id)
    access_token = FileHelper.get_google_access_token(chat_id)
    folder_id = FileHelper.get_google_drive_folder_id(chat_id)

    upload_file(file_name, file_content, folder_id, access_token)
  end

  def upload_files(chat_id, files) do
    access_token = FileHelper.get_google_access_token(chat_id)
    folder_id = FileHelper.get_google_drive_folder_id(chat_id)

    Enum.map(files, fn
      %DownloadedFile{file_name: file_name, file_content: file_content} ->
        upload_file(file_name, file_content, folder_id, access_token)
    end)
  end

  defp upload_file(file_name, file_content, folder_id, access_token) do
    metadata = %{
      name: file_name,
      parents: [folder_id]
    }

    upload_resumable({:binary, file_content}, metadata, byte_size(file_content), access_token)
  end

  def upload_file(chat_id, file_path) do
    # settings = SettingsStore.get(chat_id)
    # oauth = FileHelper.get_google_oauth(chat_id)
    access_token = FileHelper.get_google_access_token(chat_id)
    folder_id = FileHelper.get_google_drive_folder_id(chat_id)

    metadata = %{
      name: Path.basename(file_path),
      parents: [folder_id]
    }

    %{size: size} = File.stat!(file_path)

    upload_resumable({:file, file_path}, metadata, size, access_token)
  end

  defp upload_resumable(source, metadata, total_size, access_token) do
    with {:ok, session_url} <- create_resumable_session(metadata, total_size, access_token) do
      case upload_chunks(source, session_url, total_size, access_token, 0) do
        {:ok, body} = result ->
          Logger.info(
            "Google Drive upload succeeded, file_name: #{metadata.name}, body: #{inspect(body)}"
          )

          result

        result ->
          result
      end
    end
  end

  defp create_resumable_session(metadata, total_size, access_token) do
    encoded_metadata = Jason.encode!(metadata)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json; charset=UTF-8"},
      {"X-Upload-Content-Type", "application/octet-stream"},
      {"X-Upload-Content-Length", Integer.to_string(total_size)},
      {"Content-Length", Integer.to_string(byte_size(encoded_metadata))}
    ]

    case post("/upload/drive/v3/files", encoded_metadata,
           query: [uploadType: @upload_type],
           headers: headers
         ) do
      {:ok, %{status: status, headers: headers}} when status in 200..299 ->
        case header_value(headers, "location") do
          nil -> {:error, :missing_resumable_upload_location}
          session_url -> {:ok, session_url}
        end

      response ->
        handle_response(response)
    end
  end

  defp upload_chunks(_source, _session_url, total_size, _access_token, offset)
       when offset >= total_size do
    {:error, :unexpected_resumable_upload_completion}
  end

  defp upload_chunks(source, session_url, total_size, access_token, offset) do
    chunk = read_chunk!(source, offset, min(@chunk_size, total_size - offset))
    chunk_size = byte_size(chunk)
    next_offset = offset + chunk_size

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Length", Integer.to_string(chunk_size)},
      {"Content-Range", "bytes #{offset}-#{next_offset - 1}/#{total_size}"}
    ]

    case put(session_url, chunk, headers: headers) do
      {:ok, %{status: 308, headers: headers}} ->
        upload_chunks(source, session_url, total_size, access_token, next_offset(headers))

      {:ok, %{status: status} = response} when status in [200, 201] ->
        handle_response({:ok, response})

      response ->
        handle_response(response)
    end
  end

  defp read_chunk!({:binary, file_content}, offset, chunk_size) do
    binary_part(file_content, offset, chunk_size)
  end

  defp read_chunk!({:file, file_path}, offset, chunk_size) do
    File.open!(file_path, [:read], fn file ->
      {:ok, ^offset} = :file.position(file, offset)
      IO.binread(file, chunk_size)
    end)
  end

  defp header_value(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp next_offset(headers) do
    case header_value(headers, "range") do
      nil ->
        0

      "bytes=" <> range ->
        range
        |> String.split("-", parts: 2)
        |> List.last()
        |> String.to_integer()
        |> Kernel.+(1)
    end
  end

  defp handle_response({:ok, %{status: 200, body: %{"files" => files}}}) do
    {:ok, files}
  end

  defp handle_response({:ok, %{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: 201, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.warning("Failed at Google Drive, status: #{status}, body: #{inspect(body)}")
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Failed at Google Drive, reason: #{inspect(reason)}")
    {:error, reason}
  end
end
