defmodule SaveIt.SmallHelper.UrlHelper do
  def validate_url!(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and uri.host do
      url
    else
      raise ArgumentError, "Invalid URL: #{url}"
    end
  end
end
