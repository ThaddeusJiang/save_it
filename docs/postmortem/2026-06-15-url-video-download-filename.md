# Downloaded Resource Filename Policy

## What happened

Downloaded resource filenames had multiple rules. Ordinary URL downloads used a URL hash plus a `content-type`-derived extension, Cobalt tunnel downloads could keep the upstream filename from `Content-Disposition`, HLS downloads used another URL hash, and generated video covers derived names from the video filename. This made YouTube Shorts and other edge cases harder to reason about.

## Root cause

Filename generation was spread across `SmallSdk.WebDownloader`, `SmallSdk.HlsDownloader`, and `SaveIt.VideoUpload`. Each site made a slightly different decision about the basename and extension source. The basename policy and extension policy were coupled, so fixing one case risked changing another case.

## Fix applied

Filename generation is now centralized in `SaveIt.DownloadedFileName`. Downloaded resources use a random UUIDv7 basename. The extension comes from the original filename or URL path when available, including `Content-Disposition` for tunnel downloads; `content-type` is only a fallback when the original source has no extension. HLS output and generated video covers also use UUIDv7 basenames with their output extensions.

## What we learned

The simple invariant is easier to maintain than per-source filename rules: generated basename, original extension. Tests should assert the UUIDv7 shape and extension instead of depending on deterministic hash names or upstream basenames.
