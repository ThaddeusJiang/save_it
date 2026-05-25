---
name: acceptance-testing
description: Use Docker Compose to build and run the acceptance environment for `save_it`.
metadata:
  short-description: Acceptance testing with Docker
---

# Acceptance Testing

Use this skill when the user asks for an acceptance testing flow based on Docker.

## What It Does

1. Build the local acceptance image: `save_it:ac`
2. Start the acceptance stack with Docker Compose
3. Run `save_it` on the Compose network with `.env`
4. Inspect logs and stop the stack cleanly after verification

## Commands

```bash
mise run build
docker compose up -d cobalt-api typesense typelens
docker compose --profile prod up --build save_it
```

## Notes

- `docker compose --profile prod up --build save_it` uses the local `Dockerfile` and tags the result as `save_it:ac`
- `save_it` reads `.env` through `env_file` in `docker-compose.yml`
- In Compose, `save_it` uses container-safe service URLs:
  - `COBALT_API_URL=http://cobalt-api:9000`
  - `TYPESENSE_URL=http://typesense:8108`
- `typelens` is optional for app boot, but useful during acceptance checks
- The `prod` profile requires `.env` to exist at the repository root

## Log And Cleanup

```bash
docker compose --profile prod logs -f save_it
docker compose down
```

## Checklist

- Image `save_it:ac` builds successfully
- Compose services start on the same project network
- `save_it` boots with `.env`
- Required dependencies are reachable from `save_it`
