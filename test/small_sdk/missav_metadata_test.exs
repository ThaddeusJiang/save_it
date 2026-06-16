defmodule SmallSdk.MissavMetadataTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SmallSdk.MissavMetadata

  test "fetches mirror metadata for missav.ai URLs" do
    reason = {:preview_page_status, 403}

    fetch_metadata = fn fallback_url, opts ->
      send(self(), {:fallback_fetch, fallback_url, opts})

      {:ok,
       %{
         title: "MissAV Mirror OG Title",
         description: "MissAV Mirror OG Description",
         keywords: ["missav", "metadata", "fallback"],
         image_url: "https://fourhoi.com/sdam-101-uncensored-leak/cover-n.jpg"
       }}
    end

    log =
      capture_log(fn ->
        assert {:ok, metadata} =
                 MissavMetadata.fetch_fallback_metadata(
                   "https://missav.ai/ja/sdam-101-uncensored-leak?token=secret",
                   reason,
                   [],
                   fetch_metadata
                 )

        assert metadata.title == "MissAV Mirror OG Title"
      end)

    assert_receive {:fallback_fetch, "https://missav.ws/ja/sdam-101-uncensored-leak?token=secret",
                    []}

    assert log =~ "Link preview metadata fallback selected"
    assert log =~ ~s(page_url="https://missav.ai/ja/sdam-101-uncensored-leak")
    assert log =~ ~s(fallback_url="https://missav.ws/ja/sdam-101-uncensored-leak")
    assert log =~ "reason={:preview_page_status, 403}"
    refute log =~ "token=secret"
  end

  test "does not handle non-missav URLs" do
    fetch_metadata = fn _url, _opts ->
      flunk("non-missav URL should not be fetched")
    end

    assert {:error, :blocked} =
             MissavMetadata.fetch_fallback_metadata(
               "https://example.com/ja/sdam-101-uncensored-leak",
               :blocked,
               [],
               fetch_metadata
             )
  end
end
