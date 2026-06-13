# Similar Uploaded Media Echo

## What happened

When a user uploaded media with `/similar`, the bot could send the uploaded media back to the same Telegram chat as one of the similar results. This made the chat appear to contain duplicate photos.

## Root cause

The bot indexes the uploaded media in Typesense before running the similarity search. Typesense can return that newly created document as the nearest match, but the bot did not filter the query media out of the result list before sending media back to Telegram.

## Fix applied

The bot now keeps the created document response associated with the uploaded media metadata and excludes search results with the same Telegram `file_id` or Typesense document `id` before rendering similar media results.

## What we learned

Similarity searches that index the query item as part of the request flow must explicitly remove the query item from returned candidates before presenting results to users.
