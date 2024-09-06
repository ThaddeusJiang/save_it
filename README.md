# save_it

A telegram bot who save what you love in internet.

## supported services

- [x] https://x.com/
- [x] https://instagram.com/
- [x] https://www.youtube.com/
- [x] https://www.pinterest.com/

## Usage

Just send the link to the bot.

## Build with

- [Elixir](https://elixir-lang.org/)
- [ex_gram](https://github.com/rockneurotiko/ex_gram)
- [cobalt api](https://github.com/imputnet/cobalt/blob/current/docs/api.md)

## Development

```sh
# install
mix deps.get
```

```sh
# run
export TELEGRAM_BOT_TOKEN=
export GOOGLE_OAUTH_CLIENT_ID=
export GOOGLE_OAUTH_CLIENT_SECRET=

iex -S mix run --no-halt
```
