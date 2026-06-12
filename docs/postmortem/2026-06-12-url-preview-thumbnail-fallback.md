# URL Preview Thumbnail Fallback

## What happened

A user sent a bad.news URL that displayed a link preview thumbnail in Telegram. The bot tried to download the HLS video, found every available variant too large for Telegram upload, and then reported the HLS failure instead of saving the visible preview image.

## Root cause

The existing thumbnail fallback only handled media that Telegram includes in Bot API updates with a downloadable `file_id`, such as message photos or media thumbnails. For plain text URL messages, Telegram can show a client-side link preview while the Bot API update only includes `link_preview_options.url`; it does not include a thumbnail `file_id`. The fallback therefore returned `:no_thumbnail` even though the source webpage exposed a preview image through Open Graph metadata and the video poster.

## Fix applied

The link failure path still prefers Telegram-provided thumbnails when a `file_id` exists. If Telegram does not include thumbnail media, the bot now fetches the preview page, extracts `og:image`, `twitter:image`, or `video poster`, downloads that image, sends it back as the saved media, indexes it in Typesense with the original URL, writes it to local storage, and uploads it through the existing save path.

## What we learned

Seeing a preview in Telegram does not guarantee that Bot API delivered a downloadable thumbnail. Link fallback should treat Telegram message media and webpage preview metadata as separate recovery sources.
