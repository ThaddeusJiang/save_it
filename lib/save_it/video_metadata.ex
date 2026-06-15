defmodule SaveIt.VideoMetadata do
  @moduledoc false

  require Logger

  def probe_file_content(file_content, file_name) when is_binary(file_content) do
    with_temp_file(file_name, file_content, &probe_file/1)
  end

  def probe_file(file_path) when is_binary(file_path) do
    args = [
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=width,height,duration,sample_aspect_ratio,display_aspect_ratio:stream_tags=rotate:stream_side_data=rotation:format=duration",
      "-of",
      "json",
      file_path
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {json, 0} ->
        decode_ffprobe_json(json)

      {output, exit_code} ->
        {:error, {:ffprobe_failed, exit_code, output}}
    end
  rescue
    error in ErlangError ->
      {:error, {:ffprobe_unavailable, error}}
  end

  def decode_ffprobe_json(json) do
    with {:ok, decoded} <- Jason.decode(json),
         %{} = stream <- decoded |> Map.get("streams", []) |> List.first(),
         {:ok, width} <- positive_integer(stream["width"]),
         {:ok, height} <- positive_integer(stream["height"]) do
      duration =
        stream["duration"] ||
          get_in(decoded, ["format", "duration"])

      {display_width, display_height} =
        stream
        |> display_dimensions(width, height)
        |> rotate_dimensions(rotation(stream))

      metadata =
        %{
          width: display_width,
          height: display_height,
          duration: duration_integer(duration)
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      {:ok, metadata}
    else
      {:error, reason} ->
        {:error, reason}

      error ->
        {:error, {:invalid_ffprobe_output, error}}
    end
  end

  defp display_dimensions(stream, width, height) do
    ratio_dimensions(width, height, stream["display_aspect_ratio"]) ||
      sample_aspect_dimensions(width, height, stream["sample_aspect_ratio"]) ||
      {width, height}
  end

  defp rotate_dimensions({width, height}, rotation) when rotation in [90, 270, -90, -270],
    do: {height, width}

  defp rotate_dimensions({width, height}, _rotation), do: {width, height}

  defp rotation(stream) do
    [
      get_in(stream, ["tags", "rotate"]),
      side_data_rotation(stream["side_data_list"])
    ]
    |> Enum.find_value(&integer_value/1)
    |> Kernel.||(0)
  end

  defp side_data_rotation(side_data_list) when is_list(side_data_list) do
    Enum.find_value(side_data_list, &Map.get(&1, "rotation"))
  end

  defp side_data_rotation(_side_data_list), do: nil

  defp duration_integer(nil), do: nil

  defp duration_integer(value) when is_integer(value) and value > 0, do: value

  defp duration_integer(value) do
    case Float.parse(to_string(value)) do
      {seconds, _rest} when seconds > 0 -> round(seconds)
      _ -> nil
    end
  end

  defp ratio_dimensions(_width, height, ratio) do
    case positive_ratio(ratio) do
      {:ok, numerator, denominator} -> {round(height * numerator / denominator), height}
      _ -> nil
    end
  end

  defp sample_aspect_dimensions(width, height, ratio) do
    case positive_ratio(ratio) do
      {:ok, numerator, denominator} -> {round(width * numerator / denominator), height}
      _ -> nil
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) do
    case Integer.parse(to_string(value)) do
      {integer, _rest} when integer > 0 -> {:ok, integer}
      _ -> {:error, :missing_video_dimensions}
    end
  end

  defp integer_value(nil), do: nil
  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) do
    case Integer.parse(to_string(value)) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end

  defp positive_ratio(value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [numerator, denominator] ->
        with {:ok, numerator} <- positive_integer(numerator),
             {:ok, denominator} <- positive_integer(denominator) do
          {:ok, numerator, denominator}
        end

      _ ->
        :error
    end
  end

  defp positive_ratio(_value), do: :error

  defp with_temp_file(file_name, file_content, fun) do
    tmp_dir =
      Path.join(System.tmp_dir!(), "save-it-video-metadata-#{System.unique_integer([:positive])}")

    tmp_path = Path.join(tmp_dir, file_name)

    try do
      File.mkdir_p!(tmp_dir)
      File.write!(tmp_path, file_content)
      fun.(tmp_path)
    after
      case File.rm_rf(tmp_dir) do
        {:ok, _files} ->
          :ok

        {:error, reason, _file} ->
          Logger.warning("Failed to remove temp video metadata file: #{inspect(reason)}")
      end
    end
  end
end
