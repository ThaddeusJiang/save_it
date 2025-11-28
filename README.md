# Save it

Telegram bot can Save and Search pictures by link.

## Features

- [x] Save pictures via a link
- [x] Search pictures using semantic search
- [x] Find similar pictures by picture

## supported services

- [x] https://x.com/
- [x] https://www.pinterest.com/
- [x] https://instagram.com/
- [x] https://www.youtube.com/

## Usage

### Save Pictures

Just send the link to the bot.

https://github.com/user-attachments/assets/4a375cab-7124-44f3-994e-0cb026476d39

### Search Pictures

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
- [cobalt](https://github.com/imputnet/cobalt)
- [Typesense](https://typesense.org/)

## Development

```sh
# Install
mix deps.get
```

```sh
# Setup
docker compose up
```

```sh
# Run
export TELEGRAM_BOT_TOKEN=<YOUR_TELEGRAM_BOT_TOKEN>

iex -S mix run --no-halt
```

### Update Zeabur Template

```sh
just update-zeabur-template
```

https://zeabur.com/docs/template/template-in-code

## Tools

- [zeabur](https://zeabur.com/)
- [just](https://github.com/casey/just)
