# Saved GIFs Delivered as Documents Instead of Animations

## What happened

Saving a GIF link (for example an X post whose media is a GIF) produced a Telegram message with a downloadable file attachment. Users could not see the animation in the chat and had to download the file to view it.

## Root cause

`SaveIt.Bot` already routed `.gif` files to `ExGram.send_animation/3`, so the bug was not in the send branch selection. Telegram only renders an uploaded GIF as an animation when its own server-side GIF-to-mp4 conversion succeeds; for a large GIF the API silently returns a message that contains only a `document`, which clients show as a file.

Verified against the Bot API with the reported media (a ~18 MB GIF from X):

- `sendAnimation` with the original GIF returned a message with `document` only.
- `sendAnimation` with the same content transcoded locally to mp4 returned a message with `animation`.

A second, related gap: a GIF above the 50 MB Bot API upload limit hit the generic "file too large" path and was never sent, even though transcoding shrinks such files by an order of magnitude.

## Fix applied

`SaveIt.AnimationUpload` transcodes GIF content to a Telegram-friendly mp4 with ffmpeg (`libx264`, `yuv420p`, even dimensions, `+faststart`, no audio) and probes width/height/duration. `SaveIt.Bot` sends that mp4 with `sendAnimation` and the probed dimensions, and falls back to the original GIF bytes when ffmpeg is unavailable or fails. Oversized GIFs now go through the same conversion before the upload-size check, so they are sent whenever the converted mp4 fits.

Tests cover the URL download flow (GIF in, `sendAnimation` with converted mp4 out), the oversized-GIF path, and the conversion fallback behavior.

## What we learned

A successful Bot API response does not mean the media was delivered in the requested type. When a media type depends on Telegram's server-side conversion, prepare the upload locally instead of relying on it, and assert on the returned message's media field when verifying.
