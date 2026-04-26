defmodule SmallSdk.BadNews do
  require Logger

  @base_url "https://bad.news"

  @doc """
  Extract the main video download URL from a bad.news topic page.

  Returns:
    - `{:ok, video_url}` for direct mp4 videos
    - `{:ok, m3u8_url, :hls}` for HLS streams
    - `{:error, reason}` on failure
  """
  def get_download_url(page_url) do
    case Req.get(page_url, headers: [{"User-Agent", "Mozilla/5.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        extract_video_info(body)

      {:ok, %{status: status}} ->
        {:error, "bad.news returned status #{status}"}

      {:error, reason} ->
        Logger.error("Failed to fetch bad.news page: #{inspect(reason)}")
        {:error, "Failed to fetch bad.news page"}
    end
  end

  def bad_news_url?(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host == "bad.news" or String.ends_with?(host, ".bad.news")

      _ ->
        false
    end
  end

  defp extract_video_info(html) do
    # Match the first <video> element with data-source and data-type attributes
    video_regex =
      ~r/<video[^>]*?data-source="([^"]+)"[^>]*?data-type="([^"]+)"/s

    case Regex.run(video_regex, html) do
      [_, source, "mp4"] ->
        {:ok, ensure_absolute_url(source)}

      [_, source, "m3u8"] ->
        {:ok, ensure_absolute_url(source), :hls}

      _ ->
        # Try reversed attribute order
        reversed_regex =
          ~r/<video[^>]*?data-type="([^"]+)"[^>]*?data-source="([^"]+)"/s

        case Regex.run(reversed_regex, html) do
          [_, "mp4", source] ->
            {:ok, ensure_absolute_url(source)}

          [_, "m3u8", source] ->
            {:ok, ensure_absolute_url(source), :hls}

          _ ->
            {:error, "No video found on bad.news page"}
        end
    end
  end

  defp ensure_absolute_url(url) do
    if String.starts_with?(url, "http") do
      url
    else
      @base_url <> url
    end
  end
end
