defmodule SaveIt.FileHelperTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper

  setup do
    previous_data_dir = Application.get_env(:save_it, :data_dir)

    data_dir =
      Path.join(
        System.tmp_dir!(),
        "save_it_file_helper_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:save_it, :data_dir, data_dir)

    on_exit(fn ->
      restore_env(:data_dir, previous_data_dir)
      File.rm_rf!(data_dir)
    end)

    %{data_dir: data_dir}
  end

  test "stores downloaded file cache under configured data directory", %{data_dir: data_dir} do
    download_url = "https://example.com/photo.jpg"
    hashed_url = hashed_url(download_url)

    FileHelper.write_file("photo.jpg", "photo-body", download_url)

    assert File.read(Path.join([data_dir, "storage", "files", "photo.jpg"])) ==
             {:ok, "photo-body"}

    assert File.read(Path.join([data_dir, "storage", "urls", hashed_url])) == {:ok, "photo.jpg"}

    assert FileHelper.get_downloaded_file(download_url) ==
             Path.join([data_dir, "storage", "files", "photo.jpg"])
  end

  test "stores downloaded folders under configured data directory", %{data_dir: data_dir} do
    original_url = "https://example.com/gallery"
    hashed_url = hashed_url(original_url)

    FileHelper.write_folder(original_url, [
      %DownloadedFile{file_name: "first.jpg", file_content: "first"},
      {"second.jpg", "second"}
    ])

    assert File.read(Path.join([data_dir, "storage", "files", hashed_url, "first.jpg"])) ==
             {:ok, "first"}

    assert File.read(Path.join([data_dir, "storage", "files", hashed_url, "second.jpg"])) ==
             {:ok, "second"}

    assert FileHelper.get_downloaded_files(original_url) == [
             Path.join([data_dir, "storage", "files", hashed_url, "first.jpg"]),
             Path.join([data_dir, "storage", "files", hashed_url, "second.jpg"])
           ]
  end

  test "stores Google settings under configured data directory", %{data_dir: data_dir} do
    chat_id = 123

    FileHelper.set_google_access_token(chat_id, "access-token")
    FileHelper.set_google_device_code(chat_id, "device-code")
    FileHelper.set_google_drive_folder_id(chat_id, "folder-id")

    assert FileHelper.get_google_access_token(chat_id) == "access-token"
    assert FileHelper.get_google_device_code(chat_id) == "device-code"
    assert FileHelper.get_google_drive_folder_id(chat_id) == "folder-id"

    assert File.read(
             Path.join([data_dir, "settings", Integer.to_string(chat_id), "access_token.txt"])
           ) ==
             {:ok, "access-token"}
  end

  test "does not log successful file writes at the default level" do
    log =
      capture_log(fn ->
        FileHelper.write_file("photo.jpg", "image-bytes", "https://example.com/photo.jpg")
      end)

    refute log =~ "[notice]"
    refute log =~ "File.write succeeded"
  end

  defp hashed_url(url) do
    :crypto.hash(:sha256, url) |> Base.url_encode64(padding: false)
  end

  defp restore_env(key, nil), do: Application.delete_env(:save_it, key)
  defp restore_env(key, value), do: Application.put_env(:save_it, key, value)
end
