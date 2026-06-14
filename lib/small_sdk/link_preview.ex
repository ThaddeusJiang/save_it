defmodule SmallSdk.LinkPreview do
  @moduledoc false

  require Logger

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

  @title_patterns [
    ~r/<meta[^>]+property=["']og:title["'][^>]+(?:content|value)=["']([^"']+)["']/i,
    ~r/<meta[^>]+(?:content|value)=["']([^"']+)["'][^>]+property=["']og:title["']/i
  ]

  def download_image(page_url) when is_binary(page_url) do
    case get_image_url(page_url) do
      {:ok, image_url} -> WebDownloader.download_file(image_url)
      {:error, reason} -> {:error, reason}
    end
  end

  def download_image(_page_url), do: {:error, :missing_preview_url}

  def get_image_url(page_url) when is_binary(page_url) do
    case get_metadata(page_url) do
      {:ok, %{image_url: image_url}} when is_binary(image_url) -> {:ok, image_url}
      {:ok, _metadata} -> {:error, :no_preview_image}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_image_url(_page_url), do: {:error, :missing_preview_url}

  def get_description(page_url) when is_binary(page_url) do
    case get_metadata(page_url) do
      {:ok, %{description: description}} when is_binary(description) -> {:ok, description}
      {:ok, _metadata} -> {:error, :no_preview_description}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_description(_page_url), do: {:error, :missing_preview_url}

  def get_title(page_url) when is_binary(page_url) do
    case get_metadata(page_url) do
      {:ok, %{title: title}} when is_binary(title) -> {:ok, title}
      {:ok, _metadata} -> {:error, :no_preview_title}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_title(_page_url), do: {:error, :missing_preview_url}

  def get_metadata(page_url) when is_binary(page_url) do
    case Req.get(page_url, headers: [{"User-Agent", "Mozilla/5.0"}]) do
      {:ok, %{status: status, body: body}} when status in 200..209 and is_binary(body) ->
        metadata = get_metadata_from_html(page_url, body)
        log_metadata(page_url, metadata)
        {:ok, metadata}

      {:ok, %{status: status}} ->
        reason = {:preview_page_status, status}
        log_metadata_error(page_url, reason)
        {:error, reason}

      {:error, reason} ->
        log_metadata_error(page_url, reason)
        {:error, reason}
    end
  end

  def get_metadata(_page_url), do: {:error, :missing_preview_url}

  def get_metadata_from_html(page_url, html) when is_binary(page_url) and is_binary(html) do
    %{
      title: html |> extract_title() |> blank_to_nil(),
      description: html |> extract_description() |> blank_to_nil(),
      image_url:
        html |> extract_image_url() |> resolve_image_url_value(page_url) |> blank_to_nil()
    }
  end

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

  def get_title_from_html(html) when is_binary(html) do
    case extract_title(html) do
      title when is_binary(title) and title != "" -> {:ok, title}
      _ -> {:error, :no_preview_title}
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

  defp extract_title(html) do
    Enum.find_value(@title_patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, title] -> normalize_html_value(title)
        _ -> nil
      end
    end)
  end

  defp resolve_image_url_value(nil, _page_url), do: nil

  defp resolve_image_url_value(image_url, page_url) do
    case resolve_image_url(image_url, page_url) do
      {:ok, url} -> url
      {:error, _reason} -> nil
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value

  defp log_metadata(page_url, metadata) do
    Logger.info(
      "Link preview metadata fetched: " <>
        "page_url=#{format_log_url(page_url)} " <>
        "og_title=#{format_log_value(metadata.title)} " <>
        "og_description=#{format_log_value(metadata.description)} " <>
        "og_image=#{format_log_url(metadata.image_url)}",
      kind: :link_preview
    )
  end

  defp log_metadata_error(page_url, reason) do
    Logger.warning(
      "Link preview metadata fetch failed: " <>
        "page_url=#{format_log_url(page_url)} " <>
        "reason=#{format_log_reason(reason)}",
      kind: :link_preview
    )
  end

  defp format_log_url(nil), do: "nil"

  defp format_log_url(url) when is_binary(url) do
    url
    |> remove_query_and_fragment()
    |> format_log_value()
  end

  defp format_log_value(nil), do: "nil"

  defp format_log_value(value) when is_binary(value) do
    value
    |> truncate_log_value()
    |> inspect()
  end

  defp format_log_reason(reason) do
    reason
    |> inspect()
    |> truncate_log_value()
  end

  defp truncate_log_value(value) do
    if String.length(value) > 160 do
      String.slice(value, 0, 160) <> "..."
    else
      value
    end
  end

  defp remove_query_and_fragment(url) do
    uri = URI.parse(url)

    %URI{uri | query: nil, fragment: nil}
    |> URI.to_string()
  rescue
    _ -> url
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
