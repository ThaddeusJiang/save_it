import Config

config :tesla, :adapter, Tesla.Adapter.Hackney

config :tesla, Tesla.Middleware.Logger, debug: false

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
