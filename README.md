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
# Install
mix deps.get
```

```sh
# Start typesense
docker compose up
```

```sh
# Create .env file
cp .env.template .env
```

Run app

```sh
sh start.sh
```
