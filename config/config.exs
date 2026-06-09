import Config

config :tesla, :adapter, Tesla.Adapter.Hackney

env_config = "#{config_env()}.exs"

if File.exists?(Path.join(__DIR__, env_config)) do
  import_config env_config
end
