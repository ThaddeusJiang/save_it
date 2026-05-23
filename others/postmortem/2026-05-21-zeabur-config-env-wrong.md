# 2026-05-21

## Postmortem: Zeabur 下载 X 多图时只成功一张

### Summary
- Symptom: Same X URL can download multiple images in local, but only one image in Zeabur.
- Error log:

```elixir
Request failed: %Req.TransportError{reason: :timeout}
** (RuntimeError) Request failed
(save_it 0.3.0) lib/small_sdk/typesense.ex:157: SmallSdk.Typesense.handle_response/1
(save_it 0.3.0) lib/save_it/bot.ex:369: SaveIt.Bot.process_url/2
```

### Impact
- Multi-image flow in production was interrupted after the first image.
- User experience degraded for X/Twitter gallery links.

### Root Cause
- Zeabur `save_it` service had incorrect environment variable configuration.
- `save_it` could not reliably access Typesense with the expected runtime values.
- During multi-image processing, indexing request timed out and raised an exception, which stopped the remaining images in that batch.

### Why Local Was Fine
- Local env variables were correct, so Typesense requests completed normally.
- The behavior difference came from environment config mismatch, not downloader logic.

### Fix
- Corrected Zeabur environment variables for `save_it` service:
  - `TYPESENSE_URL`
  - `TYPESENSE_API_KEY`
  - (also verified `COBALT_API_URL` and `TELEGRAM_BOT_TOKEN`)

### Verification
- Re-ran the same X URL in Zeabur after env fix.
- Confirmed multiple images can be downloaded and processed end-to-end.

### Action Items
- Add a deployment checklist item: verify all required `save_it` env vars before release.
- Add startup env validation for critical keys and fail fast with explicit logs.
- Add graceful degradation around photo indexing, so a single indexing failure does not block sending remaining files.
