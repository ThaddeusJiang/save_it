defmodule SaveIt.FileHelperTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SaveIt.FileHelper

  setup do
    previous_files_dir = Application.get_env(:save_it, :storage_files_dir)
    previous_urls_dir = Application.get_env(:save_it, :storage_urls_dir)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "save_it_file_helper_test_#{System.unique_integer([:positive])}"
      )

    files_dir = Path.join(tmp_dir, "files")
    urls_dir = Path.join(tmp_dir, "urls")

    Application.put_env(:save_it, :storage_files_dir, files_dir)
    Application.put_env(:save_it, :storage_urls_dir, urls_dir)

    on_exit(fn ->
      restore_env(:storage_files_dir, previous_files_dir)
      restore_env(:storage_urls_dir, previous_urls_dir)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  test "does not log successful file writes at the default level" do
    log =
      capture_log(fn ->
        FileHelper.write_file("photo.jpg", "image-bytes", "https://example.com/photo.jpg")
      end)

    refute log =~ "[notice]"
    refute log =~ "File.write succeeded"
  end

  defp restore_env(key, nil), do: Application.delete_env(:save_it, key)
  defp restore_env(key, value), do: Application.put_env(:save_it, key, value)
end
