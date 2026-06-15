defmodule SaveIt.VideoUploadTest do
  use ExUnit.Case, async: false

  alias SaveIt.VideoUpload

  setup do
    previous_save_it = Application.get_all_env(:save_it)

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "generates square-pixel cover using the video display ratio" do
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.CoverGenerator)

    assert {:ok, cover} =
             VideoUpload.cover({:file_content, "video-bytes", "clip.mp4"}, %{
               width: 180,
               height: 640
             })

    assert cover.file_content == "cover-bytes"
    assert_uuidv7_filename(cover.file_name, ".jpg")
    assert_received {:cover_dimensions, %{width: 90, height: 320}}
  end

  defp assert_uuidv7_filename(file_name, extension) do
    assert file_name =~
             Regex.compile!(
               "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}#{Regex.escape(extension)}$"
             )
  end

  defmodule CoverGenerator do
    def cover_file_content(_file_content, _file_name, dimensions) do
      send(self(), {:cover_dimensions, dimensions})
      {:ok, "cover-bytes"}
    end
  end

  defp restore_env(app, previous_env) do
    app
    |> Application.get_all_env()
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(previous_env, fn {key, value} ->
      Application.put_env(app, key, value)
    end)
  end
end
