FROM elixir:1.17.2 AS base

ENV MIX_ENV=prod

FROM base AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release

FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    ffmpeg \
    libncurses6 \
    libstdc++6 \
    openssl \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8

WORKDIR /app

RUN useradd --system --create-home --home-dir /app save_it

COPY --from=build --chown=save_it:save_it /app/_build/prod/rel/save_it /app

USER save_it

CMD ["/app/bin/save_it", "start"]
