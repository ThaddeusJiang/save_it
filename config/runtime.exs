import Config

config :save_it, :telegram_bot_token, System.get_env("TELEGRAM_BOT_TOKEN")
config :ex_gram, token: System.get_env("TELEGRAM_BOT_TOKEN")

config :save_it, :cobalt_api_url, System.get_env("COBALT_API_URL", "http://localhost:9001")

config :save_it, :typesense_url, System.get_env("TYPESENSE_URL", "http://localhost:8101")
config :save_it, :typesense_api_key, System.get_env("TYPESENSE_API_KEY", "xyz")

# optional
config :save_it, :google_oauth_client_id, System.get_env("GOOGLE_OAUTH_CLIENT_ID")
config :save_it, :google_oauth_client_secret, System.get_env("GOOGLE_OAUTH_CLIENT_SECRET")
