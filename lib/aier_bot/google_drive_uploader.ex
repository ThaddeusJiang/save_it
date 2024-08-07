defmodule AierBot.GoogleDriveUploader do
  @moduledoc """
  TODO:
  - [ ] list folders
  - [ ] select folder and save folder_id
  """
  alias AierBot.FileHelper

  require Logger

  use Tesla
  plug(Tesla.Middleware.BaseUrl, "https://www.googleapis.com/upload/drive/v3/files")

  plug(Tesla.Middleware.Headers, [
    {"Content-Type", "application/json"}
  ])

  plug(Tesla.Middleware.JSON)

  @upload_type "multipart"
  @folder_id "1QH9q7YQ0_Bi8B9gJ_Z9ioGHlCeyg-cBI"

  def upload_file_content(chat_id, file_content, file_name) do
    IO.puts("upload_file_content started, file_name: #{file_name}")

    # oauth = FileHelper.get_google_oauth(chat_id)
    access_token = FileHelper.get_google_access_token(chat_id)

    metadata = %{
      name: file_name,
      parents: [@folder_id]
    }

    boundary = "foo_bar_baz"
    multipart_body = build_multipart_body(metadata, file_content, boundary)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "multipart/related; boundary=#{boundary}"}
    ]

    post("/", multipart_body,
      query: [uploadType: @upload_type],
      headers: headers
    )
    |> handle_response()
  end

  # def upload_file(file_path, file_name, folder_id \\ @folder_id) do
  def upload_file(chat_id, file_path) do
    IO.puts("upload_file started, file_path: #{file_path}")

    # settings = SettingsStore.get(chat_id)
    # oauth = FileHelper.get_google_oauth(chat_id)
    access_token = FileHelper.get_google_access_token(chat_id)

    metadata = %{
      # name: file_name,
      name: Path.basename(file_path),
      parents: [@folder_id]
    }

    file_content = File.read!(file_path)
    boundary = "foo_bar_baz"
    multipart_body = build_multipart_body(metadata, file_content, boundary)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "multipart/related; boundary=#{boundary}"}
    ]

    post("/", multipart_body,
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
