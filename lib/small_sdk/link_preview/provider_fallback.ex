defmodule SmallSdk.LinkPreview.ProviderFallback do
  @moduledoc false

  @providers [SmallSdk.MissavMetadata]

  def fetch_metadata(page_url, reason, opts, fetch_metadata) do
    case Enum.find(@providers, & &1.supports?(page_url)) do
      nil ->
        {:error, reason}

      provider ->
        provider.fetch_fallback_metadata(page_url, reason, opts, fetch_metadata)
    end
  end
end
