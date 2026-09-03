defmodule SaveIt.Bot.TextHelper do
  @moduledoc false

  @url_regex ~r/http[s]?:\/\/[^\s]+/

  def extract_urls(str) do
    @url_regex
    |> Regex.scan(str)
    |> Enum.map(fn [url] -> url end)
  end

  def strip_urls(text) when is_binary(text) do
    text
    |> extract_urls()
    |> Enum.reduce(text, fn url, acc -> String.replace(acc, url, "") end)
    |> String.trim()
  end

  def strip_urls(_text), do: ""

  def search_command_caption?(caption) when is_binary(caption) do
    String.contains?(caption, "/search")
  end

  def search_command_caption?(_caption), do: false

  def searchable_caption(caption) do
    if search_command_caption?(caption), do: "", else: strip_urls(caption)
  end

  def normalize_command_text(text) when is_binary(text), do: String.trim(text)
  def normalize_command_text(_text), do: ""

  def present?(text) when is_binary(text), do: String.trim(text) != ""
  def present?(_text), do: false

  def format_unix_time(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  def format_unix_time(_timestamp), do: nil
end
