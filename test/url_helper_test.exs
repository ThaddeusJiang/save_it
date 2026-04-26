defmodule SaveIt.SmallHelper.UrlHelperTest do
  use ExUnit.Case, async: true

  alias SaveIt.SmallHelper.UrlHelper

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
