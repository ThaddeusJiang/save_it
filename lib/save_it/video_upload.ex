defmodule SaveIt.VideoUpload do
  @moduledoc false

  require Logger

  alias SaveIt.VideoMetadata

  def prepare({:file_content, file_content, file_name})
      when is_binary(file_content) and is_binary(file_name) do
    case preparer().prepare_file_content(file_content, file_name) do
      {:ok, prepared_content, metadata} ->
        {{:file_content, prepared_content, file_name}, metadata}

      {:error, reason} ->
        Logger.warning("Skipping video faststart preparation: #{inspect(reason)}")
        {{:file_content, file_content, file_name}, probe_file_content(file_content, file_name)}
    end
  end

  def prepare({:file, file_path}) when is_binary(file_path) do
    file_name = Path.basename(file_path)

    case File.read(file_path) do
      {:ok, file_content} ->
        prepare({:file_content, file_content, file_name})

      {:error, reason} ->
        Logger.warning("Skipping video metadata probing: #{inspect(reason)}")
        {{:file, file_path}, %{}}
    end
  end

  defp probe_file_content(file_content, file_name) do
    case metadata_probe().probe_file_content(file_content, file_name) do
      {:ok, metadata} ->
        metadata

      {:error, reason} ->
        Logger.warning("Skipping video metadata probing: #{inspect(reason)}")
        %{}
    end
  end

  defp preparer do
    Application.get_env(:save_it, :video_upload_preparer, __MODULE__.FFmpegFaststart)
  end

  defp metadata_probe do
    Application.get_env(:save_it, :video_metadata_probe, VideoMetadata)
  end

  defmodule FFmpegFaststart do
    @moduledoc false

    def prepare_file_content(file_content, file_name)
        when is_binary(file_content) and is_binary(file_name) do
      with_temp_files(file_name, file_content, fn input_path, output_path ->
        args = [
          "-y",
          "-i",
          input_path,
          "-map",
          "0",
          "-c",
          "copy",
          "-movflags",
          "+faststart",
          "-loglevel",
          "warning",
          output_path
        ]

        with {_output, 0} <- System.cmd("ffmpeg", args, stderr_to_stdout: true),
             {:ok, prepared_content} <- File.read(output_path) do
          {:ok, prepared_content, probe_metadata(prepared_content, file_name)}
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
        Path.join(System.tmp_dir!(), "save-it-video-upload-#{System.unique_integer([:positive])}")

      input_path = Path.join(tmp_dir, "input#{Path.extname(file_name)}")
      output_path = Path.join(tmp_dir, file_name)

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
