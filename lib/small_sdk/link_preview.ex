defmodule SmallSdk.LinkPreview do
  @moduledoc false

  alias SmallSdk.WebDownloader

  @preview_patterns [
    ~r/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i,
    ~r/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i,
    ~r/<meta[^>]+name=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["']/i,
    ~r/<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image(?::src)?["']/i,
    ~r/<video[^>]+poster=["']([^"']+)["']/i
  ]

  def download_image(page_url) when is_binary(page_url) do
    case get_image_url(page_url) do
      {:ok, image_url} -> WebDownloader.download_file(image_url)
      {:error, reason} -> {:error, reason}
    end
  end

  def download_image(_page_url), do: {:error, :missing_preview_url}

  def get_image_url(page_url) when is_binary(page_url) do
    case Req.get(page_url, headers: [{"User-Agent", "Mozilla/5.0"}]) do
      {:ok, %{status: status, body: body}} when status in 200..209 and is_binary(body) ->
        body
        |> extract_image_url()
        |> resolve_image_url(page_url)

      {:ok, %{status: status}} ->
        {:error, {:preview_page_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_image_url(_page_url), do: {:error, :missing_preview_url}

  defp extract_image_url(html) do
    Enum.find_value(@preview_patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, url] -> html_unescape(url)
        _ -> nil
      end
    end)
  end

  defp resolve_image_url(nil, _page_url), do: {:error, :no_preview_image}

  defp resolve_image_url(image_url, page_url) do
    page_url
    |> URI.parse()
    |> URI.merge(image_url)
    |> URI.to_string()
    |> then(&{:ok, &1})
  rescue
    _ -> {:error, :invalid_preview_image_url}
  end

  defp html_unescape(value) do
    String.replace(value, "&amp;", "&")
  end
end
