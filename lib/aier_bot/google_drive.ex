defmodule AierBot.GoogleDrive do
  @moduledoc """
  TODO:
  - [ ] list folders
  - [ ] select folder and save folder_id
  """
  alias AierBot.FileHelper

  require Logger

  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://www.googleapis.com")

  plug(Tesla.Middleware.Headers, [
    {"Content-Type", "application/json"}
  ])

  plug(Tesla.Middleware.JSON)

  @upload_type "multipart"

  # TODO: can not list folders, Docs is lie. ref: https://developers.google.com/drive/api/guides/search-files
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

    post("/upload/drive/v3/files", multipart_body,
      query: [uploadType: @upload_type],
      headers: headers
    )
    |> handle_response()
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

    file_content = File.read!(file_path)
    boundary = "foo_bar_baz"
    multipart_body = build_multipart_body(metadata, file_content, boundary)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "multipart/related; boundary=#{boundary}"}
    ]

    post("/upload/drive/v3/files", multipart_body,
      query: [uploadType: @upload_type],
      headers: headers
    )
    |> handle_response()
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

  defp handle_response(
         {:ok,
          %Tesla.Env{
            status: 200,
            body: %{"files" => files}
          }}
       ) do
    IO.puts("handle_response, files: #{inspect(files)}")
    {:ok, files}
  end

  defp handle_response({:ok, %Tesla.Env{status: 200, body: body}}) do
    IO.puts("handle_response, body: #{inspect(body)}")
    {:ok, body}
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) do
    IO.puts("handle_response, status: #{status}, body: #{inspect(body)}")
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    IO.puts("handle_response, reason: #{inspect(reason)}")
    {:error, reason}
  end
end
