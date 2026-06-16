defmodule SaveIt.UrlMetadata do
  @moduledoc false

  @type platform ::
          :x
          | :pinterest
          | :instagram
          | :youtube_shorts
          | :bad_news
          | :missav_ai
          | :other

  @spec platform(String.t() | nil) :: platform()
  def platform(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(host) ->
        classify_host(String.downcase(host), path || "")

      _ ->
        :other
    end
  rescue
    _ -> :other
  end

  def platform(_url), do: :other

  @spec metadata_page_url(String.t() | nil, String.t() | nil, keyword()) :: String.t() | nil
  def metadata_page_url(original_url, preview_url, opts \\ []) do
    original_url
    |> platform()
    |> metadata_page_url_for(original_url, preview_url, opts)
  end

  defp metadata_page_url_for(_platform, original_url, preview_url, opts) do
    fetch_original? = Keyword.get(opts, :fetch_original?, false)

    cond do
      is_binary(preview_url) and preview_url != "" ->
        preview_url

      fetch_original? and is_binary(original_url) and original_url != "" ->
        original_url

      true ->
        nil
    end
  end

  defp classify_host(host, path) do
    cond do
      x_host?(host) ->
        :x

      pinterest_host?(host) ->
        :pinterest

      instagram_host?(host) ->
        :instagram

      youtube_shorts_host?(host, path) ->
        :youtube_shorts

      bad_news_host?(host) ->
        :bad_news

      missav_ai_host?(host) ->
        :missav_ai

      true ->
        :other
    end
  end

  defp x_host?(host),
    do: host in ["x.com", "twitter.com"] or subdomain?(host, ["x.com", "twitter.com"])

  defp pinterest_host?(host) do
    host in ["pin.it", "pinterest.com"] or
      subdomain?(host, ["pin.it", "pinterest.com"]) or
      Regex.match?(~r/(^|\.)pinterest\.[a-z.]+$/, host)
  end

  defp instagram_host?(host), do: host == "instagram.com" or subdomain?(host, ["instagram.com"])

  defp youtube_shorts_host?(host, path) do
    host == "youtu.be" or
      subdomain?(host, ["youtu.be"]) or
      ((host == "youtube.com" or subdomain?(host, ["youtube.com"])) and
         String.starts_with?(path, "/shorts/"))
  end

  defp bad_news_host?(host), do: host == "bad.news" or subdomain?(host, ["bad.news"])

  defp missav_ai_host?(host), do: host == "missav.ai" or subdomain?(host, ["missav.ai"])

  defp subdomain?(host, domains) do
    Enum.any?(domains, &String.ends_with?(host, ".#{&1}"))
  end
end
