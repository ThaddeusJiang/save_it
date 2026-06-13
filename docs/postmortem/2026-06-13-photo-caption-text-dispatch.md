# Photo Caption Text Dispatch

## What happened

A directly uploaded Telegram photo with the caption `short-text` was saved to Typesense with an empty `caption`, so `/search short` could not find it through caption full-text search.

## Root cause

ExGram dispatches non-command media captions as `{:text, caption, message}` events. The bot had a `{:message, %{photo: ...}}` handler that indexed `message.caption`, but its generic `{:text, text, message}` handler only processed URLs. When a captioned photo arrived as a text event without URLs, the handler returned `:ok` before the uploaded-photo indexing path ran.

## Fix applied

Added a dedicated `{:text, text, %{photo: ...}}` handler before the generic text URL handler. It reuses the existing uploaded-photo flow and passes the text payload as the caption, so directly uploaded photos are indexed with their Telegram captions regardless of whether ExGram emits them as message or text events.

## What we learned

Telegram captions should be treated as message metadata and as text events when using ExGram. Media-specific text handlers need to appear before generic text handlers so captions are not mistaken for ordinary URL-less text messages.
