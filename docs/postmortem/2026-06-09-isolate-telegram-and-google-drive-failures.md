# Isolate Telegram and Google Drive Failures

## What happened

Telegram and Google Drive uploads were coupled in the download completion flow. A Telegram send failure could escape as an exception and prevent the bot from treating the URL as failed cleanly. Google Drive upload failures were ignored, while attempts without Google login still tried to call the Drive API. Even after the first fix, the two delivery channels were still executed serially, so Google Drive waited for Telegram to complete.

## Root cause

The bot assumed Telegram file sends succeeded by pattern matching on `{:ok, message}` and did not convert send failures into normal error tuples. Google Drive uploads did not distinguish between "user is not logged in" and "logged-in upload failed", so the bot had no reliable signal for when to notify Telegram. The orchestration also lived inline in the bot flow, which made the delivery order serial by default.

## Fix applied

Telegram sends now return `:ok` or `{:error, reason}` without crashing the download handler. The original user message is deleted only after at least one URL completes successfully through Telegram. Google Drive uploads now skip early when the user is not logged in, and logged-in upload failures update the existing progress message without affecting the Telegram delivery. Telegram and Google Drive delivery now live in independent modules, `SaveIt.TelegramDelivery` and `SaveIt.GoogleDriveDelivery`, and each module owns its own send, result handling, failure normalization, and user-facing error message. The bot only starts both module tasks, waits for their outcomes, and updates the shared progress message with reason lines such as `Send to telegram failed, ...` and `Send to google drive failed, ...`.

## What we learned

Optional delivery channels need explicit result and execution boundaries. Each integration should report its own success or failure without assuming another channel can clean up after it, and independent channels should be started independently instead of being ordered by convenience in the bot flow.
