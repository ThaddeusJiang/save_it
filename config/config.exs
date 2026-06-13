import Config

config :logger, level: :info

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:status, :file_id, :kind],
  colors: [
    enabled: true,
    debug: :cyan,
    info: :green,
    warning: :yellow,
    error: :red
  ]

env_config = Path.expand("#{config_env()}.exs", __DIR__)

if File.exists?(env_config) do
  import_config "#{config_env()}.exs"
end
