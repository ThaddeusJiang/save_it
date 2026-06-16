# Video Detail Command

## What happened

Replying to a saved video message with `/detail` did not show the saved video metadata. The bot treated the replied message as unsupported and answered with the photo-only usage hint instead of looking up the video by its Telegram `file_id`.

## Root cause

The `/detail` command handler only inspected `reply_to_message.photo`. Saved videos are indexed in the same Typesense `photos` collection and already use their video `file_id` as the lookup key, but the command routing never extracted `reply_to_message.video.file_id`.

## Fix applied

The detail command now extracts a media `file_id` from replied photos or videos, then reuses the existing Typesense lookup and detail message rendering. The command description and usage fallback now refer to media instead of only photos.

## What we learned

Commands that read saved media should dispatch on the shared saved-media contract, not on a photo-only Telegram payload shape. Detail, delete, and future media commands should keep photo and video routing explicit when they rely on Telegram reply payloads.
