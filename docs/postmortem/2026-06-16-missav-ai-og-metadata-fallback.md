# MissAV AI Open Graph Metadata Fallback

## What happened

A `missav.ai` URL could show a rich Telegram client preview, but `save_it` could not reliably save the page's Open Graph title, description, keywords, or image URL into Typesense. URL-only saves therefore had no user caption and no searchable URL metadata.

## Root cause

Telegram client previews do not mean the Bot API exposes the resolved Open Graph fields to the bot. `save_it` still has to fetch the preview page itself. Direct server-side requests to the affected `missav.ai` page returned a Cloudflare 403 page, so `SmallSdk.LinkPreview.get_metadata/1` returned an error and the bot indexed the saved media without URL metadata.

The MissAV provider strategy recognized `missav.ai`, but it did not have a metadata fallback URL when the primary host blocked preview fetches.

## Fix applied

`SmallSdk.LinkPreview` now tries the normal preview URL first. When a `missav.ai` metadata fetch fails, it retries the same path on a configurable MissAV metadata fallback host, defaulting to `https://missav.ws`. Metadata parsed from the fallback page still flows through the existing `title`, `description`, `keywords`, and `thumbnail_url` fields, while the saved document keeps the original `missav.ai` URL.

Regression coverage now verifies both the `LinkPreview` fallback behavior and the full bot save path that writes MissAV Open Graph metadata into the Typesense document.

## What we learned

Telegram's visible link preview is not a reliable data source for bot indexing. Provider-specific metadata recovery should live at the link-preview boundary so the rest of the save pipeline can keep the same field semantics and continue preserving the user's original URL.
