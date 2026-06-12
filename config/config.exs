import Config

config :tesla, :adapter, Tesla.Adapter.Hackney

config :tesla, Tesla.Middleware.Logger, debug: false

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [],
  colors: [
    enabled: true,
    debug: :cyan,
    info: :green,
    warning: :yellow,
    error: :red
  ]
