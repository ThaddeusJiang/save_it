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

# 运行项目
CMD ["mix", "run", "--no-halt"]
