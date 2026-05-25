# Deployment

[![Deploy on Zeabur](https://zeabur.com/button.svg)](https://zeabur.com/templates/FTAONK)

## Environment Variables

```shell
TELEGRAM_BOT_TOKEN=

COBALT_API_URL=
TYPESENSE_URL=
TYPESENSE_API_KEY=

SENTRY_DSN=

# optional
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
```

## Docker Image

- Published image: `ghcr.io/thaddeusjiang/save_it`
- Zeabur template image tag: `latest`
- Local acceptance build check: `mise run build`
- Local Docker Compose stores Typesense data in the named volume `save_it_typesense_data`, so data is reused across worktrees on the same machine
