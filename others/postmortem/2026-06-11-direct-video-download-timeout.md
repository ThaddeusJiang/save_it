# Direct Video Download Timeout

## What happened

A forwarded Telegram video produced a successful `getFile` response with a `videos/*.mp4` file path, but the subsequent file content download returned `{:error, :timeout}`. The bot process raised a runtime error and stopped handling the update.

## Root cause

The direct video backup path used `SmallSdk.Telegram.download_file_content!/1` for the optional original video download. The bang call converted transient download failures into process crashes, even though the thumbnail had already been indexed in Typesense.

## Fix applied

The direct video backup path now uses the non-bang `download_file_content/1` call. When the original video download fails, the bot logs a warning, skips local and Google Drive backup for the original file, and keeps the thumbnail-based Typesense record.

## What we learned

A successful Telegram `getFile` response only confirms that Telegram returned a file path. It does not guarantee that downloading the file content will succeed, so optional media backups must handle content download failures without affecting searchable indexing.
