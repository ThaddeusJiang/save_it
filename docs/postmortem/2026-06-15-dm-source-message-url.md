# Private DM Source Message URLs

## What happened

Media saved from a private DM with the bot could include a `source_message_url` like `https://t.me/<username>/<message_id>`. That URL shape is valid for public chats with message links, but it does not jump to a specific message inside a private one-on-one bot DM.

## Root cause

The source message URL builder treated any chat with a `username` as a public Telegram peer and generated a public `t.me/<username>/<message_id>` message URL. Telegram Bot API private chats can also include a user `username`, so DM saves were misclassified.

Telegram's official deep links documentation describes message links as links to specific messages in public or private groups and channels. It documents user links for opening a chat/profile, but not a supported direct URL to jump to a specific message in a private DM.

Reference: https://core.telegram.org/api/links#message-links

## Fix applied

Source message URL generation now checks `chat.type`. When Telegram marks the source chat as `private`, the bot does not write `source_message_url` into Typesense. Public username chats and private supergroup/channel `t.me/c/...` links keep their existing behavior.

## What we learned

Telegram usernames are not enough to decide whether a message link can be built. The chat type must participate in URL generation, and private DM messages should be recorded as having no direct jump URL instead of storing a misleading public-message URL.
