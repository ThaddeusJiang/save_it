# Cobalt tunnel host mismatch

## What happened

Sending `https://x.com/lalisa4K/status/2057481649609453909?s=20` to the bot failed during download.

Cobalt successfully resolved the post and returned a tunnel response:

```json
{
  "status": "tunnel",
  "url": "http://cobalt-api:9000/tunnel?...",
  "filename": "twitter_2057481649609453909.jpg"
}
```

When the bot runs outside the Docker network and calls Cobalt through `http://localhost:9001`, the returned `http://cobalt-api:9000/tunnel?...` URL is not resolvable from the bot process.

## Root cause

`SmallSdk.Cobalt.get_download_url/1` treated every response with a `url` field as a directly usable download URL. For Cobalt tunnel responses, the URL host is derived from Cobalt's own `API_URL` setting, which can differ from the host configured in `save_it` as `:cobalt_api_url`.

That mismatch made the next `WebDownloader.download_file/1` request fail before reaching Cobalt.

## Fix applied

Tunnel responses are now handled explicitly. When Cobalt returns `status: "tunnel"`, `save_it` rewrites the tunnel URL's scheme, host, and port to match the configured `:cobalt_api_url`, while preserving the tunnel path and query.

This keeps Docker-internal deployments unchanged and makes local host-based runs use the reachable published Cobalt endpoint.

## What we learned

Cobalt tunnel URLs should be treated as callback URLs to the same Cobalt API endpoint that `save_it` is configured to call. Direct media URLs and picker item URLs should remain untouched.
