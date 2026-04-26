FROM elixir:1.17.2

RUN apt-get update && \
    apt-get install -y \
    build-essential \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix do local.hex --force, local.rebar --force, deps.get

COPY . .

CMD ["mix", "run", "--no-halt"]
