import Config

config :aier_bot, :telegram_bot_token, System.fetch_env!("TELEGRAM_BOT_TOKEN")
config :aier_bot, :aier_api_token, System.fetch_env!("AIER_API_TOKEN")
config :aier_bot, :openai_api_key, System.fetch_env!("OPENAI_API_KEY")

config :ex_gram, token: System.fetch_env!("TELEGRAM_BOT_TOKEN")
