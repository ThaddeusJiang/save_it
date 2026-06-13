defmodule SaveIt.FileHelperTest do
  use ExUnit.Case, async: false

  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper

  setup %{tmp_dir: tmp_dir} do
    previous_save_it = Application.get_all_env(:save_it)
    Application.put_env(:save_it, :data_dir, tmp_dir)

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    %{data_dir: tmp_dir}
  end

  @tag :tmp_dir
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

  @tag :tmp_dir
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

  @tag :tmp_dir
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

  defp hashed_url(url) do
    :crypto.hash(:sha256, url) |> Base.url_encode64(padding: false)
  end

  defp restore_env(app, env) do
    Application.get_all_env(app)
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(env, fn {key, value} ->
      Application.put_env(app, key, value)
    end)
  end
end
