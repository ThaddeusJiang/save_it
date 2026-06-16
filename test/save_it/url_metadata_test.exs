defmodule SaveIt.UrlMetadataTest do
  use ExUnit.Case, async: true

  alias SaveIt.UrlMetadata

  test "classifies supported URL platforms" do
    assert UrlMetadata.platform("https://x.com/example/status/1") == :x
    assert UrlMetadata.platform("https://twitter.com/example/status/1") == :x
    assert UrlMetadata.platform("https://www.pinterest.com/pin/1") == :pinterest
    assert UrlMetadata.platform("https://pin.it/abc123") == :pinterest
    assert UrlMetadata.platform("https://www.instagram.com/reel/1") == :instagram
    assert UrlMetadata.platform("https://www.youtube.com/shorts/clip123") == :youtube_shorts
    assert UrlMetadata.platform("https://youtu.be/clip123") == :youtube_shorts
    assert UrlMetadata.platform("https://bad.news/post/1") == :bad_news
    assert UrlMetadata.platform("https://missav.ai/video/1") == :missav_ai
    assert UrlMetadata.platform("https://example.com/post/1") == :other
  end

  test "selects Telegram preview URL before the original URL" do
    assert UrlMetadata.metadata_page_url(
             "https://example.com/post/1",
             "https://telegram-preview.example/post/1",
             fetch_original?: true
           ) == "https://telegram-preview.example/post/1"
  end

  test "uses the original URL only when requested" do
    assert UrlMetadata.metadata_page_url("https://example.com/post/1", nil, fetch_original?: true) ==
             "https://example.com/post/1"

    assert UrlMetadata.metadata_page_url("https://example.com/post/1", nil,
             fetch_original?: false
           ) == nil
  end
end
