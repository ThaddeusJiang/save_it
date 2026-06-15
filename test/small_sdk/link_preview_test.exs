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

  test "extracts an og title" do
    html = """
    <html>
      <head>
        <meta property="og:title" content="YouTube Page OG Title" />
      </head>
    </html>
    """

    assert LinkPreview.get_title_from_html(html) == {:ok, "YouTube Page OG Title"}
  end

  test "extracts preview metadata from html" do
    html = """
    <html>
      <head>
        <meta property="og:title" content="Preview Page OG Title" />
        <meta property="og:description" content="Preview Page OG Description" />
        <meta property="og:image" content="/preview.jpg" />
      </head>
    </html>
    """

    assert LinkPreview.get_metadata_from_html("https://example.com/posts/1", html) == %{
             title: "Preview Page OG Title",
             description: "Preview Page OG Description",
             keywords: nil,
             image_url: "https://example.com/preview.jpg"
           }
  end

  test "extracts og title, og description, and meta keywords from html" do
    html = """
    <html>
      <head>
        <meta property="og:title" content="MissAV OG Title" />
        <meta property="og:description" content="MissAV OG Description" />
        <meta name="keywords" content="missav, sdam-101, uncensored leak" />
        <meta property="og:image" content="/cover-n.jpg" />
      </head>
    </html>
    """

    assert LinkPreview.get_metadata_from_html(
             "https://missav.ai/ja/sdam-101-uncensored-leak",
             html
           ) ==
             %{
               title: "MissAV OG Title",
               description: "MissAV OG Description",
               keywords: "missav, sdam-101, uncensored leak",
               image_url: "https://missav.ai/cover-n.jpg"
             }
  end

  test "builds MissAV fallback metadata from the page URL" do
    assert LinkPreview.get_metadata_from_url_fallback(
             "https://missav.ai/ja/sdam-101-uncensored-leak"
           ) ==
             {:ok,
              %{
                title: "SDAM-101 Uncensored Leak",
                description: nil,
                keywords: nil,
                image_url: "https://fourhoi.com/sdam-101-uncensored-leak/cover-n.jpg"
              }}
  end
end
