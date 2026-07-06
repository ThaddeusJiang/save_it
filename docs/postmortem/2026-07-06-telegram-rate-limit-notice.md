# Telegram Rate Limit Notice

## What happened

When Telegram returned a `429 Too Many Requests` response while the bot was sending the initial URL download progress message, the bot process crashed with a `MatchError`. Users did not receive a clear explanation that Telegram was rate limiting the bot, and the URL save was not retried automatically after Telegram's retry window.

## Root cause

The URL save path assumed the first `sendMessage` call always returned `{:ok, progress_message}`. ExGram correctly returned `{:error, %ExGram.Error{code: 429, metadata: %{parameters: %{retry_after: seconds}}}}`, but the bot did not handle that error shape before pattern matching the success tuple.

## Fix applied

Telegram text feedback now detects `429` errors, extracts `retry_after`, and logs the limit. For URL saves, the initial progress-message boundary returns the structured rate-limit result to the URL workflow. The workflow schedules one background retry after the Telegram retry window, sends a user-facing notice with the next automatic retry time, and then re-enters the same URL save flow.

The retry is capped at one automatic attempt. If Telegram still rate limits the retry, the bot sends a final notice after the retry window and does not schedule another retry.

Regression tests cover both the successful one-time retry and the repeated-rate-limit case that must not create an infinite retry loop.

## What we learned

Telegram API calls that exist only to keep the user informed still need explicit error handling. Progress-message failures should stop the visible workflow early, and rate-limit errors should use Telegram's `retry_after` value for user-visible retry scheduling instead of becoming generic runtime exceptions or unbounded retry loops.
