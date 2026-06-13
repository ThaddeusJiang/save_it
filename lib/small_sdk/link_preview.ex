defmodule SmallSdk.LinkPreview do
  @moduledoc false

  alias SmallSdk.WebDownloader

  @preview_patterns [
    ~r/<meta[^>]+property=["']og:image["'][^>]+(?:content|value)=["']([^"']+)["']/i,
    ~r/<meta[^>]+(?:content|value)=["']([^"']+)["'][^>]+property=["']og:image["']/i,
    ~r/<meta[^>]+name=["']twitter:image(?::src)?["'][^>]+(?:content|value)=["']([^"']+)["']/i,
    ~r/<meta[^>]+(?:content|value)=["']([^"']+)["'][^>]+name=["']twitter:image(?::src)?["']/i,
    ~r/<video[^>]+poster=["']([^"']+)["']/i
  ]

  @description_patterns [
    ~r/<meta[^>]+property=["']og:description["'][^>]+(?:content|value)=["']([^"']+)["']/i,
    ~r/<meta[^>]+(?:content|value)=["']([^"']+)["'][^>]+property=["']og:description["']/i,
    ~r/<meta[^>]+name=["']twitter:description["'][^>]+(?:content|value)=["']([^"']+)["']/i,
    ~r/<meta[^>]+(?:content|value)=["']([^"']+)["'][^>]+name=["']twitter:description["']/i,
    ~r/<meta[^>]+name=["']description["'][^>]+(?:content|value)=["']([^"']+)["']/i,
    ~r/<meta[^>]+(?:content|value)=["']([^"']+)["'][^>]+name=["']description["']/i
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
        get_image_url_from_html(page_url, body)

      {:ok, %{status: status}} ->
        {:error, {:preview_page_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_image_url(_page_url), do: {:error, :missing_preview_url}

  def get_description(page_url) when is_binary(page_url) do
    case Req.get(page_url, headers: [{"User-Agent", "Mozilla/5.0"}]) do
      {:ok, %{status: status, body: body}} when status in 200..209 and is_binary(body) ->
        get_description_from_html(body)

      {:ok, %{status: status}} ->
        {:error, {:preview_page_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_description(_page_url), do: {:error, :missing_preview_url}

  def get_image_url_from_html(page_url, html) when is_binary(page_url) and is_binary(html) do
    html
    |> extract_image_url()
    |> resolve_image_url(page_url)
  end

  def get_description_from_html(html) when is_binary(html) do
    case extract_description(html) do
      description when is_binary(description) and description != "" -> {:ok, description}
      _ -> {:error, :no_preview_description}
    end
  end

  defp extract_image_url(html) do
    Enum.find_value(@preview_patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, url] -> normalize_html_value(url)
        _ -> nil
      end
    end)
  end

  defp extract_description(html) do
    Enum.find_value(@description_patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, description] -> normalize_html_value(description)
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

  defp normalize_html_value(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.trim()
  end
end
