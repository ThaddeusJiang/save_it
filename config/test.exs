import Config

telegram_bot_token = "test-token"

config :save_it,
  telegram_bot_token: telegram_bot_token,
  telegram_bot_enabled?: false

config :ex_gram,
  token: telegram_bot_token,
  adapter: ExGram.Adapter.Req
