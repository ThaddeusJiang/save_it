# Telegram Oversized Video Upload

## What happened

Downloading a long X video succeeded, but sending it to Telegram failed during
`sendVideo` multipart upload with a closed connection.

## Root cause

Telegram Bot API uploads are limited to 50 MB for videos and other non-photo
files. The bot downloaded the full MP4 and attempted to upload it without
checking the file size first, so Telegram could close the upload connection
before returning a structured API error.

## Fix applied

The bot now checks downloaded file content and cached local files before
uploading them to Telegram. Files larger than the Bot API upload limit are not
sent to Telegram, and the user receives a clear failure message instead.

## What we learned

External upload limits should be enforced before starting multipart uploads,
especially when the remote service may terminate oversized requests without a
JSON error response.
