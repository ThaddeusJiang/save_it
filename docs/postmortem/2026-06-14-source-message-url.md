# Source Message URL for Telegram Topics

## What happened

Saved media could include a `source_message_url`, but opening the link did not always jump to the expected Telegram message. The stored `source_message_id` also appeared to be unused by the bot after indexing.

## Root cause

The source message URL builder only used the chat id and message id. For private supergroup topic messages, Telegram deep links need the topic `message_thread_id` between the internal chat id and the message id. The indexing path passed only the numeric message id into the source field helper, so the helper had no access to the thread id even when Telegram provided it on the message.

For URL downloads, the bot also sent the downloaded media without forwarding the original message thread id, so saved media could leave the source topic instead of staying next to the user request.

`source_message_id` was stored in Typesense, but the details command and bot behavior only read `source_message_url`.

## Fix applied

Source field generation now receives the Telegram message object, extracts `message_thread_id` when present, and builds private supergroup topic URLs as `https://t.me/c/<chat>/<thread>/<message>`. URL-downloaded media is sent with the original message thread id so the saved Telegram message remains in the source topic. The bot no longer writes `source_message_id` into new Typesense documents, and a Typesense migration drops the unused field from the `photos` schema while preserving rollback support.

## What we learned

Telegram message links are not described by `chat_id` and `message_id` alone once forum topics are involved. URL construction and Telegram sends should keep the original message thread context available until the final saved message is created, and stored search schema fields should be trimmed when no product behavior reads them.
