defmodule SaveIt.VideoMetadataTest do
  use ExUnit.Case, async: true

  alias SaveIt.VideoMetadata

  test "uses display aspect ratio for non-square pixel videos" do
    assert {:ok, metadata} =
             VideoMetadata.decode_ffprobe_json("""
             {
               "streams": [
                 {
                   "width": 320,
                   "height": 180,
                   "sample_aspect_ratio": "2:1",
                   "display_aspect_ratio": "32:9",
                   "duration": "1.000000"
                 }
               ],
               "format": {
                 "duration": "1.000000"
               }
             }
             """)

    assert metadata.width == 640
    assert metadata.height == 180
    assert metadata.duration == 1
  end

  test "applies rotation after display aspect ratio" do
    assert {:ok, metadata} =
             VideoMetadata.decode_ffprobe_json("""
             {
               "streams": [
                 {
                   "width": 320,
                   "height": 180,
                   "sample_aspect_ratio": "2:1",
                   "display_aspect_ratio": "32:9",
                   "duration": "1.000000",
                   "side_data_list": [
                     {
                       "rotation": 90
                     }
                   ]
                 }
               ],
               "format": {
                 "duration": "1.000000"
               }
             }
             """)

    assert metadata.width == 180
    assert metadata.height == 640
    assert metadata.duration == 1
  end
end
