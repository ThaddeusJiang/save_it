defmodule SaveIt.SmallHelper.UrlHelper do
  @media_extensions MapSet.new([
                      "jpg",
                      "jpeg",
                      "png",
                      "gif",
                      "webp",
                      "bmp",
                      "tiff",
                      "avif",
                      "svg",
                      "mp4",
                      "webm",
                      "mov",
                      "m4v",
                      "mkv",
                      "mp3",
                      "m4a",
                      "aac",
                      "wav",
                      "ogg",
                      "flac"
                    ])

  def validate_url!(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and uri.host do
      url
    else
      raise ArgumentError, "Invalid URL: #{url}"
    end
  end

  def direct_media_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        ext_from_path =
          uri.path
          |> Path.extname()
          |> String.trim_leading(".")
          |> String.downcase()

        ext_from_query =
          case uri.query do
            nil -> nil
            query -> URI.decode_query(query) |> Map.get("format")
          end

        media_extension?(ext_from_path) or media_extension?(ext_from_query)

      _ ->
        false
    end
  end

  def direct_media_url?(_), do: false

  defp media_extension?(nil), do: false

  defp media_extension?(ext) do
    ext
    |> String.downcase()
    |> then(&MapSet.member?(@media_extensions, &1))
  end
end
