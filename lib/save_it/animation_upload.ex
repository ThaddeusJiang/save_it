defmodule SaveIt.AnimationUpload do
  @moduledoc false

  require Logger

  alias SaveIt.VideoMetadata

  def prepare({:file_content, file_content, file_name})
      when is_binary(file_content) and is_binary(file_name) do
    case converter().convert_file_content(file_content, file_name) do
      {:ok, converted_content, metadata} ->
        {{:file_content, converted_content, mp4_file_name(file_name)}, metadata}

      {:error, reason} ->
        Logger.debug("Skipping animation mp4 conversion: #{inspect(reason)}")
        {{:file_content, file_content, file_name}, %{}}
    end
  end

  def prepare({:file, file_path}) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, file_content} ->
        prepare({:file_content, file_content, Path.basename(file_path)})

      {:error, reason} ->
        Logger.debug("Skipping animation mp4 conversion: #{inspect(reason)}")
        {{:file, file_path}, %{}}
    end
  end

  defp mp4_file_name(file_name), do: Path.rootname(file_name) <> ".mp4"

  defp converter do
    Application.get_env(:save_it, :animation_upload_converter, __MODULE__.FFmpegGifToMp4)
  end

  defmodule FFmpegGifToMp4 do
    @moduledoc false

    def convert_file_content(file_content, file_name)
        when is_binary(file_content) and is_binary(file_name) do
      with_temp_files(file_name, file_content, fn input_path, output_path ->
        args = [
          "-y",
          "-i",
          input_path,
          "-an",
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-crf",
          "26",
          "-pix_fmt",
          "yuv420p",
          "-vf",
          "scale=trunc(iw/2)*2:trunc(ih/2)*2",
          "-movflags",
          "+faststart",
          "-loglevel",
          "warning",
          output_path
        ]

        with {_output, 0} <- System.cmd("ffmpeg", args, stderr_to_stdout: true),
             {:ok, converted_content} <- File.read(output_path) do
          {:ok, converted_content, probe_metadata(converted_content, Path.basename(output_path))}
        else
          {output, exit_code} when is_integer(exit_code) ->
            {:error, {:ffmpeg_failed, exit_code, output}}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    rescue
      error in ErlangError ->
        {:error, {:ffmpeg_unavailable, error}}
    end

    defp metadata_probe do
      Application.get_env(:save_it, :video_metadata_probe, VideoMetadata)
    end

    defp probe_metadata(file_content, file_name) do
      case metadata_probe().probe_file_content(file_content, file_name) do
        {:ok, metadata} -> metadata
        {:error, _reason} -> %{}
      end
    end

    defp with_temp_files(file_name, file_content, fun) do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "save-it-animation-upload-#{System.unique_integer([:positive])}"
        )

      input_path = Path.join(tmp_dir, "input#{Path.extname(file_name)}")
      output_path = Path.join(tmp_dir, Path.rootname(Path.basename(file_name)) <> ".mp4")

      try do
        File.mkdir_p!(tmp_dir)
        File.write!(input_path, file_content)
        fun.(input_path, output_path)
      after
        File.rm_rf(tmp_dir)
      end
    end
  end
end
