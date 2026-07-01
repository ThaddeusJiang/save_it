defmodule SaveIt.GoogleDriveTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive

  @chunk_size 8 * 1024 * 1024

  setup %{tmp_dir: tmp_dir} do
    previous_save_it = Application.get_all_env(:save_it)

    Application.put_env(:save_it, :data_dir, tmp_dir)
    Application.put_env(:save_it, :google_api_url, "https://www.googleapis.com")
    Application.put_env(:save_it, :test_pid, self())

    Application.put_env(:save_it, :google_drive_req_options,
      adapter: &__MODULE__.request_adapter/1
    )

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "uploads file content through a resumable session in chunks" do
    chat_id = 12_345
    file_content = :binary.copy("a", @chunk_size) <> "end"

    configure_google_drive(chat_id)

    assert {:ok, %{"id" => "drive-file-id"}} =
             GoogleDrive.upload_file_content(chat_id, file_content, "large-video.mp4")

    total_size = byte_size(file_content)

    assert_receive {:google_drive_request, create_session_request}
    assert create_session_request.method == :post

    assert URI.to_string(create_session_request.url) ==
             "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"

    assert create_session_request.headers["authorization"] == ["Bearer test-drive-token"]
    assert create_session_request.headers["content-type"] == ["application/json; charset=UTF-8"]
    assert create_session_request.headers["x-upload-content-type"] == ["application/octet-stream"]

    assert create_session_request.headers["x-upload-content-length"] == [
             Integer.to_string(total_size)
           ]

    assert Jason.decode!(IO.iodata_to_binary(create_session_request.body)) == %{
             "name" => "large-video.mp4",
             "parents" => ["test-drive-folder"]
           }

    assert_receive {:google_drive_request, first_chunk_request}
    assert first_chunk_request.method == :put
    assert URI.to_string(first_chunk_request.url) == "https://uploads.example/session"
    assert first_chunk_request.headers["authorization"] == ["Bearer test-drive-token"]
    assert first_chunk_request.headers["content-type"] == ["application/octet-stream"]
    assert first_chunk_request.headers["content-length"] == [Integer.to_string(@chunk_size)]
    assert first_chunk_request.headers["content-range"] == ["bytes 0-8388607/#{total_size}"]

    assert IO.iodata_to_binary(first_chunk_request.body) ==
             :binary.part(file_content, 0, @chunk_size)

    assert_receive {:google_drive_request, final_chunk_request}
    assert final_chunk_request.method == :put
    assert URI.to_string(final_chunk_request.url) == "https://uploads.example/session"
    assert final_chunk_request.headers["authorization"] == ["Bearer test-drive-token"]
    assert final_chunk_request.headers["content-type"] == ["application/octet-stream"]
    assert final_chunk_request.headers["content-length"] == ["3"]
    assert final_chunk_request.headers["content-range"] == ["bytes 8388608-8388610/#{total_size}"]
    assert IO.iodata_to_binary(final_chunk_request.body) == "end"
  end

  test "checks resumable upload status after a timed-out chunk" do
    chat_id = 12_346
    file_content = "file content"

    Application.put_env(:save_it, :google_drive_req_options,
      adapter: &__MODULE__.timeout_after_upload_adapter/1
    )

    configure_google_drive(chat_id)

    assert {:ok, %{"id" => "drive-file-id"}} =
             GoogleDrive.upload_file_content(chat_id, file_content, "timeout-video.mp4")

    assert_receive {:google_drive_request, create_session_request}
    assert create_session_request.method == :post

    assert_receive {:google_drive_request, upload_request}
    assert upload_request.method == :put
    assert upload_request.headers["content-range"] == ["bytes 0-11/12"]

    assert_receive {:google_drive_request, status_request}
    assert status_request.method == :put
    assert URI.to_string(status_request.url) == "https://uploads.example/session"
    assert status_request.headers["authorization"] == ["Bearer test-drive-token"]
    assert status_request.headers["content-length"] == ["0"]
    assert status_request.headers["content-range"] == ["*/12"]
    assert IO.iodata_to_binary(status_request.body) == ""
  end

  def request_adapter(%Req.Request{} = request) do
    send(Application.fetch_env!(:save_it, :test_pid), {:google_drive_request, request})

    response =
      case {request.method, request.url.path, request.url.query} do
        {:post, "/upload/drive/v3/files", "uploadType=resumable"} ->
          Req.Response.new(
            status: 200,
            headers: [{"location", "https://uploads.example/session"}],
            body: ""
          )

        {:put, "/session", nil} ->
          handle_upload_chunk(request)
      end

    {request, response}
  end

  defp handle_upload_chunk(request) do
    case request.headers["content-range"] do
      ["bytes 0-8388607/8388611"] ->
        Req.Response.new(
          status: 308,
          headers: [{"range", "bytes=0-8388607"}],
          body: ""
        )

      ["bytes 8388608-8388610/8388611"] ->
        %Req.Response{status: 201, body: %{"id" => "drive-file-id"}}
    end
  end

  def timeout_after_upload_adapter(%Req.Request{} = request) do
    send(Application.fetch_env!(:save_it, :test_pid), {:google_drive_request, request})

    response =
      case {request.method, request.url.path, request.url.query, request.headers["content-range"]} do
        {:post, "/upload/drive/v3/files", "uploadType=resumable", _content_range} ->
          Req.Response.new(
            status: 200,
            headers: [{"location", "https://uploads.example/session"}],
            body: ""
          )

        {:put, "/session", nil, ["bytes 0-11/12"]} ->
          Req.TransportError.exception(reason: :timeout)

        {:put, "/session", nil, ["*/12"]} ->
          %Req.Response{status: 201, body: %{"id" => "drive-file-id"}}
      end

    {request, response}
  end

  defp configure_google_drive(chat_id) do
    FileHelper.set_google_access_token(chat_id, "test-drive-token")
    FileHelper.set_google_drive_folder_id(chat_id, "test-drive-folder")
  end

  defp restore_env(app, env) do
    app
    |> Application.get_all_env()
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(env, fn {key, value} ->
      Application.put_env(app, key, value)
    end)
  end
end
