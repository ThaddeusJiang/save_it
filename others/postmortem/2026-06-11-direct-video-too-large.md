# Direct Video Too Large

## What happened

A directly forwarded Telegram video caused the bot process to raise an `ExGram.Error` when calling `getFile` for the original video file. Telegram returned `400 Bad Request: file is too big`.

## Root cause

The direct video handler downloaded the original video before indexing the thumbnail. For videos larger than Telegram Bot API's file download limit, `ExGram.get_file!/2` raised before the thumbnail could be saved to Typesense.

## Fix applied

The video handler now indexes the Telegram video thumbnail first, then attempts the original video download for local backup and uploads it to Google Drive when Drive is configured. If Telegram refuses to provide the original video file, the bot skips the original-file backup, logs a warning, and keeps the thumbnail-based Typesense record.

## What we learned

Direct video ingestion must treat the original video file as optional because Telegram may allow the bot to receive the update while refusing Bot API file download for the original media. Thumbnail indexing should stay independent from original file download.
