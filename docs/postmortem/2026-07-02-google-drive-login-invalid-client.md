# Google Drive Login Invalid Client

## What happened

Users could get stuck after approving a Google Drive device login code. Re-running `/google_drive_login` kept returning "Failed to connect Google Drive" while runtime logs only showed a Google OAuth `401`.

## Root cause

The bot treated all Google OAuth token exchange failures as generic failures. When Google returned `invalid_client`, the saved pending device code stayed on disk, so subsequent `/google_drive_login` attempts retried the same failing token exchange instead of starting a fresh device flow.

The OAuth client module also accepted missing or blank runtime OAuth configuration, allowing the bot to start a device flow that could not complete successfully.

## Fix applied

Google OAuth configuration is now validated before any device flow request. Missing or blank `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` values return a structured error and produce an actionable Telegram message.

When Google returns `invalid_client`, the bot now clears the pending device code and tells the operator to verify that the configured client ID and secret belong to a Google OAuth client with the "TVs and Limited Input devices" application type.

## What we learned

OAuth device flow errors need separate handling because some failures are recoverable user-state problems and others are operator configuration problems. Keeping a stale pending device code after `invalid_client` hides the path back to a clean login attempt.
