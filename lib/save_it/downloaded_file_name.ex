defmodule SaveIt.DownloadedFileName do
  @moduledoc false

  def random(original, opts \\ []) when is_binary(original) and is_list(opts) do
    uuid_v7() <> extension(original, Keyword.get(opts, :fallback_extension))
  end

  def uuid_v7 do
    timestamp_ms = System.system_time(:millisecond)
    <<rand_a::12, rand_b::62, _unused::6>> = :crypto.strong_rand_bytes(10)

    uuid =
      <<timestamp_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
      |> Base.encode16(case: :lower)

    <<time_low::binary-size(8), time_mid::binary-size(4), time_high::binary-size(4),
      clock_seq::binary-size(4), node::binary-size(12)>> = uuid

    Enum.join([time_low, time_mid, time_high, clock_seq, node], "-")
  end

  defp extension(original, fallback_extension) do
    original
    |> original_extension()
    |> case do
      nil -> normalize_extension(fallback_extension)
      extension -> extension
    end
  end

  defp original_extension(original) do
    original
    |> original_path()
    |> Path.extname()
    |> blank_to_nil()
  end

  defp original_path(original) do
    case URI.parse(original) do
      %URI{path: path} when is_binary(path) and path != "" -> path
      _uri -> original
    end
  end

  defp normalize_extension(nil), do: ""
  defp normalize_extension(""), do: ""
  defp normalize_extension("." <> _rest = extension), do: extension
  defp normalize_extension(extension) when is_binary(extension), do: "." <> extension

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
