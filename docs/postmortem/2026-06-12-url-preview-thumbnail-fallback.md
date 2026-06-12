# URL Preview Thumbnail Fallback

## What happened

A user sent a bad.news URL that displayed a link preview thumbnail in Telegram. The bot tried to download the HLS video, found every available variant too large for Telegram upload, and then reported the HLS failure instead of saving the visible preview image. During follow-up review, we also found that successful URL video downloads were sent back to Telegram without storing a searchable thumbnail image in Typesense. A later check showed that some webpage Open Graph images are too low quality to use as the primary cover, so URL videos should prefer the Telegram-generated video thumbnail when Telegram provides one.

## Root cause

The existing thumbnail fallback only handled media that Telegram includes in Bot API updates with a downloadable `file_id`, such as message photos or media thumbnails. For plain text URL messages, Telegram can show a client-side link preview while the Bot API update only includes `link_preview_options.url`; it does not include a thumbnail `file_id`. The fallback therefore returned `:no_thumbnail` even though the source webpage exposed a preview image through Open Graph metadata and the video poster. Separately, the `.mp4` send path returned after `sendVideo` and never indexed a searchable preview image. An intermediate OG-first fix exposed another quality issue: some sites publish low-quality Open Graph images, so Telegram's generated video thumbnail should remain the primary URL-video cover when available. HLS success had one more gap: it sent the downloaded video without passing the original source URL into the shared video-send path, so preview indexing had no webpage URL and fell through to `:no_thumbnail`.

## Fix applied

The link failure path still prefers Telegram-provided thumbnails when a `file_id` exists. If Telegram does not include thumbnail media, the bot now fetches the preview page, extracts `og:image`, `twitter:image`, or `video poster`, downloads that image, sends it back as the saved media, indexes it in Typesense with the original URL, writes it to local storage, and uploads it through the existing save path.

For successful URL video downloads, the bot now indexes the Telegram `sendVideo` thumbnail as the preferred Typesense video record image and writes that thumbnail into local storage alongside the downloaded video. If Telegram does not provide a video thumbnail, it falls back to the original URL preview image. Directly uploaded Telegram videos continue to use the Telegram video thumbnail because they do not have a source webpage preview.

## What we learned

Seeing a preview in Telegram does not guarantee that Bot API delivered a downloadable thumbnail. Link fallback should treat Telegram message media and webpage preview metadata as separate recovery sources. Video success and video failure paths both need explicit searchable-image handling; sending media to Telegram is not the same as indexing it. For URL videos, Telegram's generated video thumbnail is usually the better primary cover; webpage preview metadata is the fallback when Telegram has no thumbnail.
