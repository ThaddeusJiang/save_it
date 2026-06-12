defmodule SaveIt.GoogleDrive do
  @moduledoc """
  Google Drive integration used by the bot for optional uploads.

  Future improvements:
  - Move the raw API client into `SmallSdk`.
  - Support browsing and selecting folders.
  """
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  require Logger

  @google_api_url "https://www.googleapis.com"
  @upload_type "multipart"

  def configured?(chat_id) do
    match?({:ok, _folder_id, _access_token}, upload_config(chat_id))
  end

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

    "/drive/v3/files"
    |> build_request()
    |> Req.get(params: query_params, headers: headers)
    |> handle_response()
  end

  def upload_file_content(chat_id, file_content, file_name) do
    case upload_config(chat_id) do
      {:ok, folder_id, access_token} ->
        upload_file(file_name, file_content, folder_id, access_token)

      :not_configured ->
        {:ok, :skipped}
    end
  end

  def upload_files(chat_id, files) do
    case upload_config(chat_id) do
      {:ok, folder_id, access_token} ->
        Enum.map(files, fn
          %DownloadedFile{file_name: file_name, file_content: file_content} ->
            upload_file(file_name, file_content, folder_id, access_token)
        end)

      :not_configured ->
        {:ok, :skipped}
    end
  end

  defp upload_file(file_name, file_content, folder_id, access_token) do
    metadata = %{
      name: file_name,
      parents: [folder_id]
    }

    boundary = "foo_bar_baz"
    multipart_body = build_multipart_body(metadata, file_content, boundary)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "multipart/related; boundary=#{boundary}"}
    ]

    "/upload/drive/v3/files"
    |> build_request()
    |> Req.post(
      body: multipart_body,
      params: [uploadType: @upload_type],
      headers: headers
    )
    |> handle_response()
  end

  def upload_file(chat_id, file_path) do
    # settings = SettingsStore.get(chat_id)
    # oauth = FileHelper.get_google_oauth(chat_id)
    case upload_config(chat_id) do
      {:ok, folder_id, access_token} ->
        upload_file_path(file_path, folder_id, access_token)

      :not_configured ->
        {:ok, :skipped}
    end
  end

  defp upload_file_path(file_path, folder_id, access_token) do
    metadata = %{
      name: Path.basename(file_path),
      parents: [folder_id]
    }

    file_content = File.read!(file_path)
    boundary = "foo_bar_baz"
    multipart_body = build_multipart_body(metadata, file_content, boundary)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "multipart/related; boundary=#{boundary}"},
      {"Content-Length", "*/*"}
      # {"Content-Length", byte_size(multipart_body) |> Integer.to_string()}
    ]

    "/upload/drive/v3/files"
    |> build_request()
    |> Req.post(
      body: multipart_body,
      params: [uploadType: @upload_type],
      headers: headers
    )
    |> handle_response()
  end

  defp upload_config(chat_id) do
    access_token = FileHelper.get_google_access_token(chat_id)
    folder_id = FileHelper.get_google_drive_folder_id(chat_id)

    if configured_value?(access_token) and configured_value?(folder_id) do
      {:ok, folder_id, access_token}
    else
      :not_configured
    end
  end

  defp configured_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp configured_value?(_value), do: false

  defp build_request(path) do
    req_options =
      :save_it
      |> Application.get_env(:google_drive_req_options, [])
      |> Keyword.put_new(
        :base_url,
        Application.get_env(:save_it, :google_api_url, @google_api_url)
      )
      |> Keyword.put_new(:retry, false)
      |> Keyword.put(:url, path)
      |> Keyword.put_new(:headers, [{"Content-Type", "application/json"}])

    Req.new(req_options)
  end

  defp build_multipart_body(metadata, file_content, boundary) do
    """
    --#{boundary}
    Content-Type: application/json; charset=UTF-8

    #{Jason.encode!(metadata)}
    --#{boundary}
    Content-Type: application/octet-stream

    #{file_content}
    --#{boundary}--
    """
  end

  defp handle_response({:ok, %{status: 200, body: %{"files" => files}}}) do
    {:ok, files}
  end

  defp handle_response({:ok, %{status: 200, body: body}}) do
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
