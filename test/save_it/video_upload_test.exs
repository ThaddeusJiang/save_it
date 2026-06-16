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

  test "generates full-size cover and Telegram-compliant thumbnail using the video display ratio" do
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.CoverGenerator)

    assert {:ok, cover} =
             VideoUpload.cover({:file_content, "video-bytes", "clip.mp4"}, %{
               width: 180,
               height: 640
             })

    assert cover.file_content == "cover-bytes"
    assert cover.thumbnail_file_content == "thumbnail-bytes"
    assert_uuidv7_filename(cover.file_name, ".jpg")
    assert_uuidv7_filename(cover.thumbnail_file_name, ".jpg")
    assert_received {:cover_dimensions, %{width: 180, height: 640, jpeg_quality: 2}}
    assert_received {:cover_dimensions, %{width: 90, height: 320, jpeg_quality: 5}}
  end

  test "caps generated covers without upscaling smaller videos" do
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.CoverGenerator)

    assert {:ok, _cover} =
             VideoUpload.cover({:file_content, "video-bytes", "clip.mp4"}, %{
               width: 2160,
               height: 3840
             })

    assert_received {:cover_dimensions, %{width: 1080, height: 1920, jpeg_quality: 2}}
    assert_received {:cover_dimensions, %{width: 180, height: 320, jpeg_quality: 5}}
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

      case dimensions.jpeg_quality do
        2 -> {:ok, "cover-bytes"}
        5 -> {:ok, "thumbnail-bytes"}
      end
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
