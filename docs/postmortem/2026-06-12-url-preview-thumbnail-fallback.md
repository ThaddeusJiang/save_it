# URL Preview Thumbnail Fallback

## What happened

A user sent a bad.news URL that displayed a link preview thumbnail in Telegram. The bot tried to download the HLS video, found every available variant too large for Telegram upload, and then reported the HLS failure instead of saving the visible preview image. During follow-up review, we also found that successful URL video downloads were sent back to Telegram without storing a searchable thumbnail image in Typesense.

## Root cause

The existing thumbnail fallback only handled media that Telegram includes in Bot API updates with a downloadable `file_id`, such as message photos or media thumbnails. For plain text URL messages, Telegram can show a client-side link preview while the Bot API update only includes `link_preview_options.url`; it does not include a thumbnail `file_id`. The fallback therefore returned `:no_thumbnail` even though the source webpage exposed a preview image through Open Graph metadata and the video poster. Separately, the `.mp4` send path returned after `sendVideo` and never indexed the video thumbnail returned by Telegram.

## Fix applied

The link failure path still prefers Telegram-provided thumbnails when a `file_id` exists. If Telegram does not include thumbnail media, the bot now fetches the preview page, extracts `og:image`, `twitter:image`, or `video poster`, downloads that image, sends it back as the saved media, indexes it in Typesense with the original URL, writes it to local storage, and uploads it through the existing save path.

For successful URL video downloads, the bot now indexes the Telegram `sendVideo` response thumbnail as a Typesense video record. If Telegram does not return a video thumbnail, it falls back to the original URL preview image, so a saved video remains discoverable by image search whenever preview metadata is available.

## What we learned

Seeing a preview in Telegram does not guarantee that Bot API delivered a downloadable thumbnail. Link fallback should treat Telegram message media and webpage preview metadata as separate recovery sources. Video success and video failure paths both need explicit searchable-image handling; sending media to Telegram is not the same as indexing it.
