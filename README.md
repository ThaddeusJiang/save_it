# Save it

A telegram bot can Save photos and Search photos

## Features

- [x] Save photos via a link
- [x] Search photos using semantic search
- [x] Find similar photos by photo

## supported services

- [x] https://x.com/
- [x] https://instagram.com/
- [x] https://www.youtube.com/
- [x] https://www.pinterest.com/

## Usage

### Save Photos

Just send the link to the bot.

https://github.com/user-attachments/assets/4a375cab-7124-44f3-994e-0cb026476d39

### Search Photos

messages:

```
/search cat
/search dog
/search girl
/similar photo
```

https://github.com/user-attachments/assets/b0dedcc0-3305-42b2-8101-6b0b5d32f17a

## Playground

https://t.me/save_it_playground

## Build with

- [Elixir](https://elixir-lang.org/)
- [ex_gram](https://github.com/rockneurotiko/ex_gram)
- [cobalt api](https://github.com/imputnet/cobalt/blob/current/docs/api.md)
- [Typesense](https://typesense.org/)

## Development

```sh
# install
mix deps.get
```

```sh
# start typesense
docker compose up
```

```sh
# modify env
export TELEGRAM_BOT_TOKEN=
export TYPESENSE_URL=
export TYPESENSE_API_KEY=

iex -S mix run --no-halt
```

Pro Tips: create shell script for fast run app

1. touch start.sh

```sh
#!/bin/sh

export TELEGRAM_BOT_TOKEN=<YOUR_TELEGRAM_BOT_TOKEN>

export TYPESENSE_URL=<YOUR_TYPESENSE_URL>
export TYPESENSE_API_KEY=<YOUR_TYPESENSE_API_KEY>

export GOOGLE_OAUTH_CLIENT_ID=<YOUR_GOOGLE_OAUTH_CLIENT_ID>
export GOOGLE_OAUTH_CLIENT_SECRET=<YOUR_GOOGLE_OAUTH_CLIENT_SECRET>

iex -S mix run --no-halt
```

2. execute permission

```sh
chmod +x start.sh
```

3. run

```sh
./start.sh
```
