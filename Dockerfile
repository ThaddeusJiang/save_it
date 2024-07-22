# 使用官方的 Elixir 镜像作为基础镜像
FROM elixir:1.17.2

# 安装必要的依赖
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 复制 mix.exs 和 mix.lock 文件并安装依赖
COPY mix.exs mix.lock ./
RUN mix do local.hex --force, local.rebar --force, deps.get

# 复制剩余的项目文件
COPY . .

# 设置环境变量（如果需要在运行时指定，可以在 docker run 命令中传递）
ENV TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
ENV AIER_API_TOKEN=$AIER_API_TOKEN
ENV OPENAI_API_KEY=$OPENAI_API_KEY

# 运行项目
CMD ["mix", "run", "--no-halt"]
