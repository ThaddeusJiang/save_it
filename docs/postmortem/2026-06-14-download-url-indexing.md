# Download URL Missing from Indexed URL Media

## What happened

URL media downloads saved to Telegram and Typesense successfully, but the indexed Typesense document did not include `download_url`. Operators could see the original page URL and Telegram source message URL, but not the resolved media URL returned by Cobalt or the HLS resolver.

## Root cause

The Typesense schema and `PhotoService` already supported `download_url`, and `WebDownloader` carried the resolved URL on `%DownloadedFile{}`. The bot send/index pipeline dropped that value: it passed only the original source URL through `bot_send_*` helpers, and video preview indexing received only `source_url`.

Multi-image downloads had the same issue because file tuples contained only the original source URL even though each downloaded file had its own resolved media URL.

## Fix applied

The download context now includes the resolved media URL when available. Bot send helpers propagate `download_url` into image, video, HLS, and multi-image Typesense documents. Multi-image indexing stores each item's own media URL. Thumbnail fallback saves still avoid writing preview-image URLs as media `download_url` values.

## What we learned

Resolved media URLs cross several boundaries: resolver, downloader, Telegram upload, thumbnail indexing, and Typesense persistence. Fields that are already present in schema still need explicit propagation through every send/index branch, especially when video indexing happens after Telegram returns the sent message.
