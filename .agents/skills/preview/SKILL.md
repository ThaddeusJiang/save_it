---
name: preview
description: Build `save_it:local`, start docker compose dependencies, then run `save_it:local` with `.env`.
metadata:
  short-description: Local preview with Docker
---

# Preview

Use this skill when the user asks for a local preview flow based on Docker.

## What It Does

1. Build image: `save_it:local`
2. Start dependencies by docker compose
3. Run app container from `save_it:local` and read `.env`

## Command

```bash
bash .agents/skills/preview/scripts/run_preview.sh
```

## Notes

- Dependencies started by compose: `cobalt-api`, `typesense`, `typelens`
- The run command reads `.env` and also sets container-network-safe defaults:
- `COBALT_API_URL=http://cobalt-api:9000`
- `TYPESENSE_URL=http://typesense:8108`

## Checklist

- Image `save_it:local` is built successfully
- Compose dependencies are up
- `save_it:local` starts with `.env`
