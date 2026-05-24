---
name: acceptance-testing
description: Build `save_it:ac`, start docker compose dependencies, then run `save_it:ac` with `.env` for acceptance testing.
metadata:
  short-description: Acceptance testing with Docker
---

# Acceptance Testing

Use this skill when the user asks for an acceptance testing flow based on Docker.

## What It Does

1. Build image: `save_it:ac`
2. Start dependencies by docker compose
3. Run app container from `save_it:ac` and read `.env`

## Command

```bash
bash .agents/skills/acceptance-testing/scripts/run_acceptance_testing.sh
```

## Notes

- Dependencies started by compose: `cobalt-api`, `typesense`, `typelens`
- The run command reads `.env` and also sets container-network-safe defaults:
- `COBALT_API_URL=http://cobalt-api:9000`
- `TYPESENSE_URL=http://typesense:8108`

## Checklist

- Image `save_it:ac` is built successfully
- Compose dependencies are up
- `save_it:ac` starts with `.env`
