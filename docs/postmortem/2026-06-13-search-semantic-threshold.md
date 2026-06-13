# Search Semantic Threshold

## What happened

Searching for `dog` returned valid caption and image matches, but the image semantic branch also included looser visual matches that were not clearly dog-related.

## Root cause

The image semantic search used `distance_threshold: 0.785`, which was too permissive for text-to-image search. A local Typesense reproduction showed the true dog image matches at distances around `0.7427`, `0.7710`, and `0.7714`, while unrelated visual matches started around `0.7788`.

## Fix applied

Reduced the image semantic search threshold to `0.775`. Caption full-text and image semantic results are still both included, with caption results first and deduplicated before image results.

## What we learned

Search precision should be tuned at the semantic distance boundary rather than by disabling semantic results whenever captions match. Caption search gives explicit textual relevance; image semantic search should remain available, but only for high-confidence visual matches.
