FROM elixir:1.17.2 AS base

ENV MIX_ENV=prod
ENV LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

FROM base AS deps

COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only ${MIX_ENV}

FROM base AS build

COPY --from=deps /root/.mix /root/.mix
COPY --from=deps /app/deps /app/deps
COPY --from=deps /app/mix.exs /app/mix.exs
COPY --from=deps /app/mix.lock /app/mix.lock

COPY config ./config
RUN mix deps.compile

COPY lib ./lib
COPY priv ./priv
RUN mix compile

COPY . .

FROM base

COPY --from=build /root/.mix /root/.mix
COPY --from=build /app /app

CMD ["mix", "run", "--no-halt"]
