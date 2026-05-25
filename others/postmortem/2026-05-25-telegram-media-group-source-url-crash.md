# Telegram Media Group Source URL Crash

## What happened

Saving a multi-image post could crash while sending the Telegram media group even though the images had already been downloaded successfully.

## Root cause

`SmallSdk.Telegram.send_media_group/2` assumed every item in `files` was a two-element tuple of `{file_name, content}`.
The bot passes downloaded multi-image files as `{file_name, content, source_url}` so it can persist the original source URL for indexing.
That mismatch caused a `FunctionClauseError` inside the reducer that builds the multipart request.

## Fix applied

Normalize media group file tuples inside `SmallSdk.Telegram.send_media_group/2` so both `{file_name, content}` and `{file_name, content, source_url}` are accepted.
Add a regression test covering the three-element tuple shape used by downloaded X media.

## What we learned

Internal transport helpers should accept the metadata-rich tuple shapes already used by bot workflows, or normalize them at the boundary before pattern matching.
