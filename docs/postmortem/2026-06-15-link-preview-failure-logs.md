# Link Preview Failure Logs Missing

## What happened

An X URL could be resolved and downloaded through Cobalt, and Typesense stored the media `download_url`, but the indexed document still had an empty caption and no `thumbnail_url`. The runtime logs only showed download and file write progress, not whether the bot fetched Open Graph title, description, or image metadata.

## Root cause

The bot relies on `SmallSdk.LinkPreview.get_metadata/1` for URL captions and public thumbnail URLs. For the affected X URL, the same helper returned `{:error, {:preview_page_status, 404}}` when requesting the preview page directly. That error path was silently converted to `nil` by the caller, and `LinkPreview` only logged successful 2xx metadata fetches. As a result, operators could not distinguish "metadata was empty" from "metadata fetch failed".

## Fix applied

`SmallSdk.LinkPreview.get_metadata/1` now logs a concise warning when the preview request returns a non-2xx status or fails at the HTTP layer. The log includes the sanitized preview page URL and the failure reason, while successful metadata logs continue to include title, description, and image URL summaries.

## What we learned

Cobalt cookies and Cobalt download success do not guarantee that the bot's separate Open Graph request can read the same X page. Link preview fetch failures need first-class logs because they directly explain missing captions and missing public thumbnail URLs.
