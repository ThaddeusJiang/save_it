# Telegram Video Aspect Ratio and Streaming Preparation

## What happened

Some videos sent through the bot displayed with an incorrect aspect ratio in Telegram, even though the original file displayed correctly when manually downloaded and uploaded. Larger videos also did not always start loading as streamable videos in Telegram clients.

## Root cause

The bot uploaded downloaded MP4 files with `supports_streaming: true`, but it did not pass video dimensions or duration to Telegram. Videos with rotation/display metadata can be misinterpreted when Telegram derives dimensions from the raw upload. The bot also sent MP4 files as downloaded, so files whose `moov` atom was not optimized for streaming were less likely to behave like streamable Telegram videos.

## Fix applied

MP4 uploads now go through a video upload preparation step before `sendVideo`:

- Use `ffmpeg -c copy -movflags +faststart` to prepare MP4 files for streaming when possible.
- Use `ffprobe` to read width, height, duration, and rotation metadata.
- Pass `width`, `height`, `duration`, and `supports_streaming` to Telegram `sendVideo`.
- Fall back to the original upload when `ffmpeg` or `ffprobe` fails, so downloads are not blocked by metadata extraction.

## What we learned

`supports_streaming` is necessary but not enough. Telegram clients also benefit from MP4 files being faststart-ready, and bots should provide explicit display dimensions for videos whose container metadata may otherwise be interpreted differently from the original player or a manual Telegram client upload.
