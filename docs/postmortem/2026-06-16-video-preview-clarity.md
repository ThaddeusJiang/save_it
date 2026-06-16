# Video Preview Clarity

## What happened

Generated video previews looked blurry in Telegram and in the saved search preview. The bot generated a square-pixel JPEG with the correct display aspect ratio, but the image was still much smaller than the source video frame.

## Root cause

The video preview pipeline used one generated image for both Telegram `cover` and `thumbnail`. That image was capped at 320 pixels on the longest side to satisfy Telegram's `thumbnail` requirements. The newer `cover` field is the visible video cover and does not need to share that low-resolution cap, so the bot was unnecessarily sending a small cover.

## Fix applied

`SaveIt.VideoUpload.cover/2` now generates a higher-resolution cover capped at 1920 pixels on the longest side without upscaling smaller videos, and also generates a separate Telegram-compliant thumbnail capped at 320 pixels. `sendVideo` uploads the high-resolution image as `cover` and the small image as `thumbnail`; Typesense indexing and oversized-video photo fallback continue to use the clearer cover image.

## What we learned

Telegram video `cover` and `thumbnail` are different API boundaries. Keep the thumbnail small and compatible, but do not let thumbnail constraints degrade the user-visible cover or search preview image.
