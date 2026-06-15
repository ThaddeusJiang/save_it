# MissAV Link Preview Metadata

## What happened

A MissAV URL could produce a downloaded video resource, but the saved caption was not stable or traceable enough. Local processing could only derive a slug fallback such as `SDAM-101 Uncensored Leak`, while Telegram's client preview showed richer metadata that was not available to the bot.

## Root cause

The initial assumption conflated Telegram client previews with data exposed to bots. `SmallSdk.LinkPreview` also did not parse `meta[name=keywords]`, and the MissAV URL fallback ran before any HTTP preview request, so a `missav.ai` URL could return a slug title without even trying to read HTML. After reversing that order, ordinary server-side requests still receive a Cloudflare `403`, which means the rich Telegram client preview is not currently available through this server-side path or the Bot API payload. For user-visible captions, the original URL is the most reliable MissAV value.

## Fix applied

`SmallSdk.LinkPreview` now fetches preview HTML before considering URL fallback, and extracts `meta[name=keywords]` in addition to the existing `og:title`, `og:description`, and preview image fields. For `missav.ai` source URLs, the bot uses the original URL as the caption while still using readable preview metadata, or the scoped MissAV fallback, for thumbnail selection and diagnostics. When the MissAV preview request is blocked, the fallback derives a readable title from the page slug, builds the cover image URL from the observed MissAV cover path pattern, and logs the fallback reason without inventing unavailable description or keyword text. Bot coverage verifies both readable and blocked MissAV preview paths keep the caption as the source URL.

## What we learned

Successful media download, Telegram client preview generation, and bot-side metadata fetching are separate capabilities. Sites protected by bot challenges can still have predictable public preview assets, but those fallbacks should stay scoped to the specific host and should log why fallback was selected. Captions should prefer values that the bot can reliably prove, rather than metadata visible only in a Telegram client preview.
