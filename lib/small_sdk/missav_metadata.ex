defmodule SmallSdk.MissavMetadata do
  @moduledoc false

  @fallback_base_url "https://missav.ws"

  require Logger

  def supports?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        missav_ai_host?(String.downcase(host))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def supports?(_url), do: false

  def fetch_fallback_metadata(page_url, reason, opts, fetch_metadata)
      when is_binary(page_url) and is_function(fetch_metadata, 2) do
    case fallback_url(page_url) do
      fallback_url when is_binary(fallback_url) ->
        log_metadata_fallback(page_url, fallback_url, reason)
        fetch_metadata.(fallback_url, opts)

      nil ->
        {:error, reason}
    end
  end

  def fetch_fallback_metadata(_page_url, reason, _opts, _fetch_metadata), do: {:error, reason}

  defp fallback_url(page_url) do
    with true <- supports?(page_url),
         %URI{host: fallback_host} = fallback_uri when is_binary(fallback_host) <-
           URI.parse(@fallback_base_url),
         %URI{} = page_uri <- URI.parse(page_url) do
      %URI{
        page_uri
        | scheme: fallback_uri.scheme,
          userinfo: fallback_uri.userinfo,
          host: fallback_host,
          port: fallback_uri.port
      }
      |> URI.to_string()
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp missav_ai_host?(host), do: host == "missav.ai" or String.ends_with?(host, ".missav.ai")

  defp log_metadata_fallback(page_url, fallback_url, reason) do
    Logger.warning(
      "Link preview metadata fallback selected: " <>
        "page_url=#{format_log_url(page_url)} " <>
        "fallback_url=#{format_log_url(fallback_url)} " <>
        "reason=#{format_log_reason(reason)}",
      kind: :link_preview
    )
  end

  defp format_log_url(url) when is_binary(url) do
    url
    |> remove_query_and_fragment()
    |> format_log_value()
  end

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
end
