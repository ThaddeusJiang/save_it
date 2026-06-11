# Link Thumbnail Fallback

## What happened

A user-sent link could fail during URL resolution or media download even when Telegram had already attached a usable thumbnail to the message. The bot reported the download failure and discarded the available thumbnail.

## Root cause

The URL download flow only passed `chat_id` and the extracted URL into `process_url/2`. Failure handlers no longer had access to the original Telegram message, so they could not inspect message photos or media thumbnails as fallback input.

## Fix applied

The URL download context now keeps the original Telegram message. When URL resolution, HLS download, multi-file download, or single-file download fails, the bot tries to download the largest Telegram-provided photo or media thumbnail, sends it back as a saved photo, indexes it in Typesense with the original URL, writes it to local storage, and uploads it to Google Drive through the existing link-save path. If the thumbnail fallback succeeds, the bot treats the operation as successful and logs the original download failure instead of sending a user-facing failure message.

## What we learned

Telegram message metadata can still contain a useful image even when the external site or downloader fails. Download fallback behavior should keep the original message available until all recovery paths have been tried.
