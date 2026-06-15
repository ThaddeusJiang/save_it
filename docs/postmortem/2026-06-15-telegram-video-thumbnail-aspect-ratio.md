# Telegram Video Thumbnail Aspect Ratio

## What happened

URL-downloaded videos were sent back to Telegram with explicit video dimensions, but the visible Telegram preview could still use a different aspect ratio from the actual video.

## Root cause

The video metadata probe read encoded `width` and `height`, plus rotation metadata, but it ignored `display_aspect_ratio` and `sample_aspect_ratio`. Videos with non-square pixels can have display dimensions that differ from their encoded pixel dimensions. The bot therefore passed dimensions to Telegram that were still not the true display ratio, so Telegram's own video preview frame could be shaped differently from the actual video.

## Fix applied

The metadata probe now requests `sample_aspect_ratio` and `display_aspect_ratio` from `ffprobe`. It derives display dimensions from that aspect ratio first, then applies rotation, and passes the resulting `width` and `height` to Telegram `sendVideo`. The bot also generates a square-pixel JPEG whose pixel ratio matches those display dimensions and uploads it as both Telegram `cover` and `thumbnail`. That generated image is used for Telegram's visible message cover and for Typesense preview indexing without storing an unrelated webpage `thumbnail_url`. If cover generation fails, the bot falls back to Telegram's returned video thumbnail, then to the webpage preview image.

## What we learned

Telegram can generate video thumbnails itself, but that server-generated thumbnail can be ignored or shaped differently from the display ratio. The visible message cover still needs accurate display dimensions and square-pixel preview pixels. Encoded pixels, sample aspect ratio, display aspect ratio, and rotation all need to be considered before deciding which `width` and `height` to send to Telegram and which JPEG preview dimensions to generate.
