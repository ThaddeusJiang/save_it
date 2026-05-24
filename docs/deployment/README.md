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
- Local acceptance build check: `mise run build-acceptance-test`
- The container now boots from the Elixir release entrypoint: `/app/bin/save_it start`

## Release Commands

- Run Typesense migration in a release container:

```sh
/app/bin/save_it eval 'SaveIt.Release.ts_migrate()'
```

- Example with Docker:

```sh
docker exec -it <container_name> /app/bin/save_it eval 'SaveIt.Release.ts_migrate()'
```
