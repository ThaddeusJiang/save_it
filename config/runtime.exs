import Config

config :save_it, :telegram_bot_token, System.fetch_env!("TELEGRAM_BOT_TOKEN")
config :ex_gram, token: System.fetch_env!("TELEGRAM_BOT_TOKEN")
config :save_it, :google_oauth_client_id, System.fetch_env!("GOOGLE_OAUTH_CLIENT_ID")
config :save_it, :google_oauth_client_secret, System.fetch_env!("GOOGLE_OAUTH_CLIENT_SECRET")
