defmodule SmallSdk.HlsDownloader do
  require Logger

  # Telegram bot API file upload limit is 50MB
  @max_file_size 49 * 1024 * 1024

  @doc """
  Download an HLS (m3u8) stream and convert it to mp4 using ffmpeg.
  Automatically selects a variant that fits within Telegram's 50MB limit.

  Returns `{:ok, filename, binary_content}` or `{:error, reason}`.
  """
  def download(m3u8_url) do
    base_url = extract_base_url(m3u8_url)

    with {:ok, master_body} <- fetch(m3u8_url),
         {:ok, variants} <- parse_master_playlist(master_body, base_url) do
      download_best_variant(variants, m3u8_url)
    end
  end

  defp download_best_variant([], _original_url) do
    {:error, "No suitable HLS variant found"}
  end

  defp download_best_variant([variant | rest], original_url) do
    filename = gen_filename(original_url) <> ".mp4"
    tmp_path = Path.join(System.tmp_dir!(), filename)

    Logger.info("HLS: trying variant #{variant.resolution} (#{variant.bandwidth} bps)")

    args =
      build_ffmpeg_args(variant, tmp_path)

    try do
      case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
        {_output, 0} ->
          case File.read(tmp_path) do
            {:ok, content} when byte_size(content) > @max_file_size ->
              Logger.warning(
                "HLS: variant #{variant.resolution} too large (#{div(byte_size(content), 1024 * 1024)}MB), trying lower quality"
              )

              File.rm(tmp_path)
              download_best_variant(rest, original_url)

            {:ok, content} when byte_size(content) > 0 ->
              {:ok, filename, content}

            {:ok, _} ->
              {:error, "ffmpeg produced an empty file"}

            {:error, reason} ->
              {:error, "Failed to read ffmpeg output: #{inspect(reason)}"}
          end

        {output, exit_code} ->
          Logger.error("ffmpeg failed (exit #{exit_code}): #{output}")
          download_best_variant(rest, original_url)
      end
    rescue
      e in ErlangError ->
        Logger.error("ffmpeg not found: #{inspect(e)}")
        {:error, "ffmpeg is not installed"}
    after
      File.rm(tmp_path)
    end
  end

  defp build_ffmpeg_args(variant, tmp_path) do
    case variant.audio_url do
      nil ->
        ["-i", variant.url, "-c", "copy", "-y", "-loglevel", "warning", tmp_path]

      audio_url ->
        [
          "-i", variant.url,
          "-i", audio_url,
          "-c", "copy",
          "-y",
          "-loglevel", "warning",
          tmp_path
        ]
    end
  end

  defp fetch(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HLS fetch failed with status #{status}"}
      {:error, reason} -> {:error, "HLS fetch failed: #{inspect(reason)}"}
    end
  end

  defp parse_master_playlist(body, base_url) do
    lines = String.split(body, "\n", trim: true)

    # Parse audio tracks: GROUP-ID -> absolute URL
    audio_map =
      lines
      |> Enum.filter(&String.starts_with?(&1, "#EXT-X-MEDIA:"))
      |> Enum.filter(&String.contains?(&1, "TYPE=AUDIO"))
      |> Enum.reduce(%{}, fn line, acc ->
        group_id = extract_attr(line, "GROUP-ID")
        uri = extract_attr(line, "URI")

        if group_id && uri do
          Map.put(acc, group_id, resolve_url(uri, base_url))
        else
          acc
        end
      end)

    # Parse video variants: resolution, bandwidth, audio group, URL
    variants =
      lines
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [info, _url] -> String.starts_with?(info, "#EXT-X-STREAM-INF:") end)
      |> Enum.map(fn [info, url_line] ->
        bandwidth = extract_attr(info, "BANDWIDTH") |> to_integer(0)
        resolution = extract_attr(info, "RESOLUTION") || "unknown"
        audio_group = extract_attr(info, "AUDIO")
        audio_url = if audio_group, do: Map.get(audio_map, audio_group)

        %{
          url: resolve_url(url_line, base_url),
          audio_url: audio_url,
          bandwidth: bandwidth,
          resolution: resolution
        }
      end)
      # Sort by bandwidth descending so we try highest quality first
      |> Enum.sort_by(& &1.bandwidth, :desc)

    case variants do
      [] -> {:error, "No variants found in HLS master playlist"}
      variants -> {:ok, variants}
    end
  end

  defp extract_attr(line, attr_name) do
    # Handle both quoted and unquoted attribute values
    regex = Regex.compile!("#{attr_name}=\"?([^\",\\s]+)\"?")

    case Regex.run(regex, line) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp to_integer(nil, default), do: default

  defp to_integer(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp extract_base_url(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}"
  end

  defp resolve_url(path, base_url) do
    if String.starts_with?(path, "http") do
      path
    else
      base_url <> path
    end
  end

  defp gen_filename(url) do
    :crypto.hash(:sha256, url) |> Base.url_encode64(padding: false)
  end
end
