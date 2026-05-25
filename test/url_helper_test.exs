defmodule SaveIt.SmallHelper.UrlHelperTest do
  use ExUnit.Case, async: true

  alias SaveIt.SmallHelper.UrlHelper

  test "normalize_optional_url/1 keeps valid http urls" do
    assert UrlHelper.normalize_optional_url("https://example.com/photo.jpg") ==
             "https://example.com/photo.jpg"
  end

  test "normalize_optional_url/1 returns nil for non-url values" do
    assert UrlHelper.normalize_optional_url(nil) == nil
    assert UrlHelper.normalize_optional_url("not-a-url") == nil
    assert UrlHelper.normalize_optional_url({:file_content, <<1, 2, 3>>, "photo.jpg"}) == nil
  end

  test "direct_media_url?/1 returns true for media extension in path" do
    assert UrlHelper.direct_media_url?(
             "https://docs.expo.dev/static/videos/tutorial/01-navigating-between-screens.mp4"
           )
  end

  test "direct_media_url?/1 returns true for media format in query" do
    assert UrlHelper.direct_media_url?(
             "https://pbs.twimg.com/media/GV52FRqaoAA-O8A?format=jpg&name=large"
           )
  end

  test "direct_media_url?/1 returns false for non media page url" do
    refute UrlHelper.direct_media_url?("https://example.com/article?id=1")
  end
end
