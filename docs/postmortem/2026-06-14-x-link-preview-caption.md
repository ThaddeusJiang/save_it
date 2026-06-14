# X Link Preview Caption Fallback

## What happened

An X link could download a video successfully, but Telegram did not show a caption derived from the page preview. The runtime logs only showed the Cobalt failure/fallback attempts and file writes, so it was unclear whether the bot had fetched Open Graph title, description, or image metadata.

## Root cause

The URL caption path fetched only the single field selected for that service. X links used `og:description`, and if the preview page did not provide a description while still providing `og:title`, the caption path returned an empty string. Because link preview extraction did not log the fetched Open Graph fields, the missing caption was hard to diagnose from local logs.

## Fix applied

Link preview fetching now extracts title, description, and image URL together and logs a concise metadata summary without dumping raw HTML. YouTube URL-only saves still use `og:title`. X and Twitter URL-only saves use `og:description` first, then fall back to `og:title` when no description is available. The bot also logs which Open Graph field was selected as the caption source.

## What we learned

Caption selection and preview image fallback both depend on the same webpage metadata, so logging only download progress is not enough. Link preview code should expose the metadata boundary clearly: what URL was fetched, which Open Graph fields were present, and which field became the user-visible caption.
