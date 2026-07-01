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
  @upload_content_type "application/octet-stream"
  @resumable_upload_chunk_size 8 * 1024 * 1024

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
        Logger.info("google_drive_upload_skipped reason=not_configured file_name=#{file_name}")

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
        Logger.info(
          "google_drive_upload_skipped reason=not_configured file_count=#{length(files)}"
        )

        {:ok, :skipped}
    end
  end

  defp upload_file(file_name, file_content, folder_id, access_token) do
    metadata = %{
      name: file_name,
      parents: [folder_id]
    }

    result =
      with {:ok, session_url} <-
             create_resumable_upload_session(metadata, byte_size(file_content), access_token) do
        upload_resumable_content(session_url, file_content, access_token)
      end

    case result do
      {:ok, _body} ->
        Logger.info("google_drive_upload_completed file_name=#{file_name}")

      {:error, reason} ->
        Logger.warning(
          "google_drive_upload_failed file_name=#{file_name} #{upload_failure_details(reason)}"
        )
    end

    result
  end

  defp upload_failure_details(%{status: status}), do: "status=#{status}"

  defp upload_failure_details(%Req.TransportError{reason: reason}),
    do: "reason=#{inspect(reason)}"

  defp upload_failure_details(reason) when is_atom(reason), do: "reason=#{reason}"
  defp upload_failure_details(_reason), do: "reason=unknown"

  def upload_file(chat_id, file_path) do
    # settings = SettingsStore.get(chat_id)
    # oauth = FileHelper.get_google_oauth(chat_id)
    case upload_config(chat_id) do
      {:ok, folder_id, access_token} ->
        upload_file_path(file_path, folder_id, access_token)

      :not_configured ->
        Logger.info(
          "google_drive_upload_skipped reason=not_configured file_name=#{Path.basename(file_path)}"
        )

        {:ok, :skipped}
    end
  end

  defp upload_file_path(file_path, folder_id, access_token) do
    file_content = File.read!(file_path)
    upload_file(Path.basename(file_path), file_content, folder_id, access_token)
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

  defp create_resumable_upload_session(metadata, file_size, access_token) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json; charset=UTF-8"},
      {"X-Upload-Content-Type", @upload_content_type},
      {"X-Upload-Content-Length", Integer.to_string(file_size)}
    ]

    "/upload/drive/v3/files"
    |> build_request()
    |> Req.post(
      body: Jason.encode!(metadata),
      params: [uploadType: "resumable"],
      headers: headers
    )
    |> handle_resumable_session_response()
  end

  defp upload_resumable_content(session_url, file_content, access_token) do
    upload_resumable_chunk(session_url, file_content, byte_size(file_content), 0, access_token)
  end

  defp upload_resumable_chunk(_session_url, _file_content, 0, 0, _access_token) do
    {:ok, %{}}
  end

  defp upload_resumable_chunk(session_url, file_content, total_size, offset, access_token)
       when offset < total_size do
    chunk_size = min(@resumable_upload_chunk_size, total_size - offset)
    chunk = :binary.part(file_content, offset, chunk_size)
    end_offset = offset + chunk_size - 1

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", @upload_content_type},
      {"Content-Length", Integer.to_string(chunk_size)},
      {"Content-Range", "bytes #{offset}-#{end_offset}/#{total_size}"}
    ]

    session_url
    |> build_request()
    |> Req.put(body: chunk, headers: headers)
    |> handle_resumable_upload_response(
      session_url,
      file_content,
      total_size,
      offset,
      access_token
    )
  end

  defp build_request(url) do
    req_options =
      :save_it
      |> Application.get_env(:google_drive_req_options, [])
      |> Keyword.put_new(:retry, false)
      |> maybe_put_base_url(url)
      |> Keyword.put(:url, url)
      |> Keyword.put_new(:headers, [{"Content-Type", "application/json"}])

    Req.new(req_options)
  end

  defp maybe_put_base_url(req_options, url) do
    if absolute_url?(url) do
      Keyword.delete(req_options, :base_url)
    else
      Keyword.put_new(
        req_options,
        :base_url,
        Application.get_env(:save_it, :google_api_url, @google_api_url)
      )
    end
  end

  defp absolute_url?(url) do
    url
    |> URI.parse()
    |> Map.get(:scheme)
    |> is_binary()
  end

  defp handle_resumable_session_response({:ok, %{status: status} = response})
       when status in [200, 201] do
    case Req.Response.get_header(response, "location") do
      [session_url | _] ->
        {:ok, session_url}

      [] ->
        Logger.error("Google Drive resumable upload session missing location")
        {:error, :missing_resumable_upload_location}
    end
  end

  defp handle_resumable_session_response(response) do
    handle_response(response)
  end

  defp handle_resumable_upload_response(
         {:ok, %{status: status, body: body}},
         _session_url,
         _file_content,
         _total_size,
         _next_offset,
         _access_token
       )
       when status in [200, 201] do
    {:ok, body}
  end

  defp handle_resumable_upload_response(
         {:ok, %{status: 308} = response},
         session_url,
         file_content,
         total_size,
         fallback_offset,
         access_token
       ) do
    offset = next_resumable_offset(response, fallback_offset)
    upload_resumable_chunk(session_url, file_content, total_size, offset, access_token)
  end

  defp handle_resumable_upload_response(
         {:error, %Req.TransportError{}},
         session_url,
         file_content,
         total_size,
         _next_offset,
         access_token
       ) do
    session_url
    |> request_resumable_upload_status(total_size, access_token)
    |> handle_resumable_status_response(session_url, file_content, total_size, access_token)
  end

  defp handle_resumable_upload_response(
         response,
         _session_url,
         _file_content,
         _total_size,
         _next_offset,
         _access_token
       ) do
    handle_response(response)
  end

  defp request_resumable_upload_status(session_url, total_size, access_token) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Length", "0"},
      {"Content-Range", "*/#{total_size}"}
    ]

    session_url
    |> build_request()
    |> Req.put(body: "", headers: headers)
  end

  defp handle_resumable_status_response(
         {:ok, %{status: status, body: body}},
         _session_url,
         _file_content,
         _total_size,
         _access_token
       )
       when status in [200, 201] do
    {:ok, body}
  end

  defp handle_resumable_status_response(
         {:ok, %{status: 308} = response},
         session_url,
         file_content,
         total_size,
         access_token
       ) do
    offset = next_resumable_offset(response, 0)
    upload_resumable_chunk(session_url, file_content, total_size, offset, access_token)
  end

  defp handle_resumable_status_response(
         response,
         _session_url,
         _file_content,
         _total_size,
         _access_token
       ) do
    handle_response(response)
  end

  defp next_resumable_offset(response, fallback_offset) do
    case Req.Response.get_header(response, "range") do
      [range | _] ->
        range
        |> String.split("-")
        |> List.last()
        |> Integer.parse()
        |> case do
          {last_byte, ""} -> last_byte + 1
          _ -> fallback_offset
        end

      [] ->
        fallback_offset
    end
  end

  defp handle_response({:ok, %{status: 200, body: %{"files" => files}}}) do
    {:ok, files}
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in [200, 201] do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.warning("Failed at Google Drive", status: status)
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Failed at Google Drive")
    {:error, reason}
  end
end
