defmodule SaveIt.IndexImage do
  @moduledoc false

  @fallback_jpeg Base.decode64!(
                   "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAJgABAAAAAAAAAAAAAAAAAAAAAxABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAAPwBH/9k="
                 )

  def fallback_jpeg, do: @fallback_jpeg

  def jpeg_bytes(file_name, file_content)
      when is_binary(file_name) and is_binary(file_content) do
    case String.downcase(Path.extname(file_name)) do
      ext when ext in [".jpg", ".jpeg", ".png"] ->
        {:ok, file_content}

      _ext ->
        converter().convert_file_content(file_content, file_name)
    end
  end

  defp converter do
    Application.get_env(:save_it, :index_image_converter, __MODULE__.FFmpegToJpeg)
  end

  defmodule FFmpegToJpeg do
    @moduledoc false

    def convert_file_content(file_content, file_name)
        when is_binary(file_content) and is_binary(file_name) do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "save-it-index-image-#{System.unique_integer([:positive])}"
        )

      input_path = Path.join(tmp_dir, "input#{Path.extname(file_name)}")
      output_path = Path.join(tmp_dir, "output.jpg")

      try do
        File.mkdir_p!(tmp_dir)
        File.write!(input_path, file_content)

        args = [
          "-y",
          "-i",
          input_path,
          "-frames:v",
          "1",
          "-q:v",
          "2",
          "-loglevel",
          "warning",
          output_path
        ]

        with {_output, 0} <- System.cmd("ffmpeg", args, stderr_to_stdout: true),
             {:ok, jpeg} <- File.read(output_path) do
          {:ok, jpeg}
        else
          {output, exit_code} when is_integer(exit_code) ->
            {:error, {:ffmpeg_failed, exit_code, output}}

          {:error, reason} ->
            {:error, reason}
        end
      after
        File.rm_rf(tmp_dir)
      end
    rescue
      error in ErlangError ->
        {:error, {:ffmpeg_unavailable, error}}
    end
  end
end
