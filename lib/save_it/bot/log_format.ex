defmodule SaveIt.Bot.LogFormat do
  @moduledoc false

  def url(nil), do: "nil"

  def url(url) when is_binary(url) do
    url
    |> remove_query_and_fragment()
    |> value()
  end

  def url(url), do: value(inspect(url))

  def value(nil), do: "nil"
  def value(value) when is_binary(value), do: inspect(value)
  def value(value), do: inspect(value)

  defp remove_query_and_fragment(url) do
    uri = URI.parse(url)

    %URI{uri | query: nil, fragment: nil}
    |> URI.to_string()
  rescue
    _error -> url
  end
end
