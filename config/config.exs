import Config

config :logger, level: :info

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:status, :file_id, :kind],
  colors: [
    enabled: true,
    debug: :cyan,
    info: :normal,
    notice: :green,
    warning: :yellow,
    error: :red
  ]

import_config "#{config_env()}.exs"
