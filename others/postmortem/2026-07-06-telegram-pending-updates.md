# Telegram Pending Updates Dropped on Startup

## What happened

When the bot was offline and a user sent multiple URL messages, restarting the bot processed only the newest pending message. Older pending URL messages disappeared from the Telegram update queue and were never saved.

## Root cause

`save_it` used ExGram's default polling worker. On startup that worker initialized its first `getUpdates` request with `offset: -1`. Telegram Bot API treats a negative offset as a request for updates from the end of the queue; `-1` returns only the latest pending update and forgets all previous updates.

This was not caused by a recent Telegram Bot API behavior change. The current Bot API still documents that omitting `offset` returns the earliest unconfirmed updates, while a negative offset discards older queued updates.

## Fix applied

`save_it` now uses `SaveIt.TelegramPolling` instead of ExGram's default polling worker. The custom worker omits `offset` on the first fetch so Telegram returns the earliest unconfirmed pending updates. After a batch is dispatched, the worker acknowledges processed updates with `max(update_id) + 1`, preserving the existing long-polling flow for future updates.

Regression tests cover both startup behavior without an initial negative offset and the follow-up fetch that acknowledges processed updates.

## What we learned

Pending Telegram update handling depends on the first polling request after startup. A negative offset is a destructive queue operation, so bot startup code should avoid it unless intentionally dropping old updates.
