defmodule SmallSdk.LinkPreviewTest do
  use ExUnit.Case, async: true

  alias SmallSdk.LinkPreview

  test "extracts a GitHub profile og image" do
    html = """
    <html>
      <head>
        <meta property="og:image" content="https://avatars.githubusercontent.com/u/17308201?v=4?s=400" />
      </head>
    </html>
    """

    assert LinkPreview.get_image_url_from_html(
             "https://github.com/Thaddeusjiang",
             html
           ) ==
             {:ok, "https://avatars.githubusercontent.com/u/17308201?v=4?s=400"}
  end

  test "extracts a Scrapbox project og image" do
    html = """
    <html>
      <head>
        <meta property="og:image" content="https://gyazo.com/e3f4b97ec5d43ec64ef4fd112c658017/max_size/2000"/>
      </head>
    </html>
    """

    assert LinkPreview.get_image_url_from_html(
             "https://scrapbox.io/ThaddeusJiang/",
             html
           ) ==
             {:ok, "https://gyazo.com/e3f4b97ec5d43ec64ef4fd112c658017/max_size/2000"}
  end

  test "extracts an og description" do
    html = """
    <html>
      <head>
        <meta property="og:description" content="Photo Page OG Description" />
      </head>
    </html>
    """

    assert LinkPreview.get_description_from_html(html) == {:ok, "Photo Page OG Description"}
  end
end
