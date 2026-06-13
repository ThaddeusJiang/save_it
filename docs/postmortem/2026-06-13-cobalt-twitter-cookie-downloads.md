# Cobalt Twitter Cookie Downloads

## What happened

A user sent an X/Twitter video URL and the bot failed to save it. The application logged a Cobalt HTTP 400 error, then reported that no thumbnail fallback was available after the link download failed.

## Root cause

The local Docker Compose Cobalt service still used the v10 image and did not provide authenticated Twitter cookies. Some X/Twitter posts require login, sensitive-content, or age-gated access, so anonymous Cobalt requests can fail before the bot has a downloadable media URL or fallback thumbnail.

An initial Compose configuration also hid the local cookie file path behind an environment fallback expression and could fall back to an example file, which made the runtime configuration harder to review.

## Fix applied

The bundled local and Zeabur Cobalt services now use the v11 image. Local Docker Compose mounts a fixed, gitignored root-level `cobalt-cookies.json` file to `/cookies.json` and sets `COOKIE_PATH=/cookies.json`. The example file remains separate as `cobalt-cookies.example.json` and is not used as the runtime default.

The README documents the local cookie file format and path, and `.gitignore` keeps real cookie files out of git.

## What we learned

For third-party download services, image version and authentication state are part of the save pipeline. Compose files should make local secret bind mounts explicit and reviewable, especially when the service failure mode looks like a generic upstream 400.
