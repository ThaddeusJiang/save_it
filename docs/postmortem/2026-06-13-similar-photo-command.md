# Similar Photo Command Crash

## What happened

Sending a photo with the `/similar` command caused the bot process to raise a `FunctionClauseError` in `SaveIt.Bot.handle/2`. The Telegram update was delivered by ExGram as `{:command, :similar, message}` with a photo payload, but the bot did not have a matching handler clause.

## Root cause

The bot supported `/similar` in two adjacent shapes:

- A `/similar` command without a photo, which asks the user to upload a photo.
- A normal photo message whose caption contains `/similar`, which uploads, indexes, and searches for similar media.

It did not support the command-event shape that ExGram can emit when the `/similar` command is attached to a photo. That left a gap between command handling and photo-message handling.

## Fix applied

Added a `{:command, :similar, %{photo: [_ | _]}}` handler that reuses the existing uploaded-photo flow and passes `"/similar"` as the command caption. This keeps indexing, similar search, self-result exclusion, and response rendering on the same path as the already-working caption-based `/similar` flow.

## What we learned

Telegram photo captions that contain bot commands can arrive as command updates, not only as ordinary photo messages with captions. Command handlers for media commands should cover the media-bearing update shape and delegate to the shared media handling path to avoid divergent behavior.
