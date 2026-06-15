# Caption Prefix Search Miss

## What happened

Searching for `short` did not return a saved Telegram photo whose caption was `short-test`, even though the caption was present in Typesense.

## Root cause

The caption branch of the federated Typesense search explicitly set `prefix` to `false`. Typesense then treated `short` as an exact token query and did not match the `short-test` caption. A direct reproduction against local Typesense showed `prefix=false` returned zero caption hits, while `prefix=true` returned the expected `short-test` document.

## Fix applied

Enabled `prefix` for the caption full-text search branch only. The image semantic search branch still keeps `prefix` disabled because it relies on the vector query.

## What we learned

Caption full-text search needs prefix matching for Telegram-style short labels and hyphenated captions. When changing Typesense query parameters, verify against a real Typesense collection in addition to request-shape unit tests.
