# Oversized URL Video Preview Indexing

## What happened

When `save_it` successfully downloaded a URL video that was larger than Telegram Bot API upload limits, the bot sent `💔 File is too large for Telegram Bot API upload.`. The downloaded video was still saved locally by the finalization path, but the user did not receive a useful preview in Telegram and no Typesense document was created for search.

## Root cause

The shared `bot_send_file/4` path checked `telegram_upload_too_large?/1` before dispatching by file extension. Oversized files returned immediately after sending the user-facing error message. For `.mp4` downloads, that early return skipped the existing video preview pipeline: metadata probing, cover generation, Telegram photo delivery, and Typesense indexing.

## Fix applied

Oversized `.mp4` downloads now take a video-specific fallback path. The bot prepares/probes the downloaded video, tries to generate a cover image, sends that image to Telegram with a note that the video was downloaded but too large to upload as a video, and indexes the preview image in Typesense as `media_type: "video"` with the original URL, resolved download URL, caption, URL metadata, and source message URL. If cover generation is unavailable, the path falls back to the existing webpage preview image logic. Non-video oversized files keep the existing too-large message behavior.

## What we learned

Upload-size checks need to happen at the media-type boundary, not before media-specific fallback behavior has a chance to run. Download success, Telegram delivery, and Typesense indexing are separate outcomes; a Telegram video upload failure should still preserve searchability when the app has enough local media data to create a preview.
