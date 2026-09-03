defmodule SaveIt.AnimationUploadTest do
  use ExUnit.Case, async: false

  alias SaveIt.AnimationUpload

  setup do
    previous_save_it = Application.get_all_env(:save_it)

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "converts GIF content to mp4 and returns the converted metadata" do
    Application.put_env(:save_it, :animation_upload_converter, __MODULE__.Converter)

    assert {{:file_content, "mp4-bytes", "animation.mp4"}, metadata} =
             AnimationUpload.prepare({:file_content, "gif-bytes", "animation.gif"})

    assert metadata == %{width: 480, height: 270, duration: 3}
    assert_received {:converted, "gif-bytes", "animation.gif"}
  end

  test "keeps the original GIF content when the conversion fails" do
    Application.put_env(:save_it, :animation_upload_converter, __MODULE__.FailingConverter)

    assert {{:file_content, "gif-bytes", "animation.gif"}, %{}} =
             AnimationUpload.prepare({:file_content, "gif-bytes", "animation.gif"})
  end

  test "keeps the original path when the file cannot be read" do
    assert {{:file, "/missing/animation.gif"}, %{}} =
             AnimationUpload.prepare({:file, "/missing/animation.gif"})
  end

  defmodule Converter do
    def convert_file_content(file_content, file_name) do
      send(self(), {:converted, file_content, file_name})

      {:ok, "mp4-bytes", %{width: 480, height: 270, duration: 3}}
    end
  end

  defmodule FailingConverter do
    def convert_file_content(_file_content, _file_name), do: {:error, :ffmpeg_failed}
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
