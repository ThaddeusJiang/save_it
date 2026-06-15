# Thumbnail URL Missing from Indexed URL Media

## What happened

URL media saves could include a searchable image thumbnail in Typesense, but the document did not keep the public thumbnail URL. Operators could inspect the original page URL and the resolved media download URL, yet could not see which Open Graph image URL was used as the preview source.

## Root cause

The bot already fetched link preview metadata for captions and webpage preview fallback images, but only the image bytes were passed into Typesense. The `og:image` URL stayed inside the link preview helper and was not propagated through the bot send/index options. Typesense also lacked a `thumbnail_url` field, so there was no schema target for the value.

Telegram-provided thumbnails need special handling because their downloadable file URLs include the bot token. Those URLs are useful for fetching bytes internally, but should not be stored as public document metadata.

## Fix applied

Typesense now has an optional `thumbnail_url` field. URL media saves reuse link preview metadata to pass public preview image URLs through the bot send/index pipeline for photos, videos, HLS videos, and webpage preview fallback saves. Telegram-only thumbnail fallbacks still avoid writing tokenized Telegram file URLs.

## What we learned

Thumbnail bytes and thumbnail source URLs are separate pieces of state. A document can have a searchable thumbnail image without having a safe public thumbnail URL, so the indexing pipeline needs to carry the URL explicitly and only persist URLs that are safe to expose.
