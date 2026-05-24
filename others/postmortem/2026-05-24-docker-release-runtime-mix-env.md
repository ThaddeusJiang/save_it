# Docker release runtime Mix.env crash

## What happened

While converting the container image from `mix run --no-halt` to a `mix release`-based image, the Docker image built successfully but failed during a release smoke test.

## Root cause

`config/runtime.exs` used `Mix.env()` for the Sentry `environment_name`. `Mix` is not available in a production release runtime, so the config provider crashed during boot.

## Fix applied

- Replaced `Mix.env()` with `config_env()` in `config/runtime.exs`
- Rebuilt the release and Docker image
- Verified the release binary inside the image with `/app/bin/save_it eval 'IO.puts("release-ok")'`

## What we learned

- A successful `mix release` build is not enough to prove a release boots correctly.
- Any code in `runtime.exs` must avoid `Mix` runtime dependencies.
- A cheap `release eval` smoke test is a good guardrail after Dockerfile or runtime config changes.
