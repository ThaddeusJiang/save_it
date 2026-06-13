# Search Semantic Fallback Noise

## What happened

Searching for `dog` returned caption matches for dog, but also included unrelated image semantic matches such as cat photos.

## Root cause

The federated Typesense search returned two result sets: caption full-text matches first, then image semantic matches. The application flattened both result sets unconditionally. That meant image semantic fallback results were appended even when the caption search had already found precise text matches.

## Fix applied

Changed search result selection to use the first non-empty federated result set. Caption full-text results now win outright when present. Image semantic results are returned only when caption search finds nothing.

## What we learned

Search priority should affect inclusion, not only ordering. For user-entered text, precise caption matches should gate semantic fallback so broader image similarity does not dilute already-correct caption results.
