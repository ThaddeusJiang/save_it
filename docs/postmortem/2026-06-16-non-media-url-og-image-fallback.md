# Non-Media URL Open Graph Image Fallback

## What happened

When a URL resolved to a downloadable resource that was not an image, video, or animation, `save_it` treated the resolved resource as a successful URL download. For article-like pages this could save and send an HTML/document file, while skipping the existing Open Graph image fallback path that would create a searchable photo preview.

## Root cause

The single-file URL download path considered any successful HTTP download complete. Media routing happened later by file extension, so non-media files were sent as Telegram documents and were not indexed in Typesense. The fallback logic that saves Telegram thumbnails or webpage `og:image` previews only ran when resolving or downloading the URL failed.

The thumbnail fallback also accepted `store_download_url?: false`, but the existing `download_url` option could remain in the keyword list. That allowed a failed or non-media resolved URL to leak into the fallback document metadata.

## Fix applied

The single-file download path now checks whether the downloaded filename is a supported URL media file before sending and finalizing it. Non-media downloads route through the existing thumbnail fallback, so pages with `og:image` are saved as photo previews and indexed with URL metadata.

Fallback sends now remove any existing `download_url` before optionally adding the intended one. This keeps fallback documents from storing the non-media resolved URL.

Metadata fetching for thumbnail fallback now fetches the original URL when no Telegram preview URL exists, so user-captioned URL pages can still store `thumbnail_url`, `title`, `description`, and `keywords`.

## What we learned

Download success is not the same as save success. URL saves need a media-type boundary before finalization so HTML or document responses can degrade to preview image saving instead of bypassing search indexing. Boolean options that suppress metadata should delete stale keyword values, not only avoid adding new ones.
