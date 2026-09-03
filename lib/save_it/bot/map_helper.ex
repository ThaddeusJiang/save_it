defmodule SaveIt.Bot.MapHelper do
  @moduledoc false

  def map_get(nil, _key), do: nil

  def map_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  def map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  def map_value(_map, _key), do: nil

  def put_optional(map, _key, nil), do: map
  def put_optional(map, key, value), do: Map.put(map, key, value)

  def put_optional_keyword(keyword, _key, nil), do: keyword
  def put_optional_keyword(keyword, key, value), do: Keyword.put(keyword, key, value)
end
