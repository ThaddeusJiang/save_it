import Config

config :save_it, :timezone, System.get_env("TZ") || "Asia/Tokyo"
config :save_it, :data_dir, System.get_env("SAVE_IT_DATA_DIR", "./data")

if config_env() != :test do
  telegram_bot_token = System.fetch_env!("TELEGRAM_BOT_TOKEN")

  config :save_it,
    telegram_bot_token: telegram_bot_token,
    start_bot?: true

  config :ex_gram,
    token: telegram_bot_token,
    adapter: ExGram.Adapter.Req
end

config :save_it, :cobalt_api_url, System.get_env("COBALT_API_URL", "http://localhost:9001")

config :save_it, :typesense_url, System.get_env("TYPESENSE_URL", "http://localhost:8108")
config :save_it, :typesense_api_key, System.get_env("TYPESENSE_API_KEY", "xyz")

# optional
config :save_it, :google_oauth_client_id, System.get_env("GOOGLE_OAUTH_CLIENT_ID")
config :save_it, :google_oauth_client_secret, System.get_env("GOOGLE_OAUTH_CLIENT_SECRET")

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  included_dependencies: [:req, :jason]
