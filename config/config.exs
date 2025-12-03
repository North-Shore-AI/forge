import Config

config :forge, Forge.Repo,
  database: "forge_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :forge, ecto_repos: [Forge.Repo]

# API server configuration (Plug.Cowboy)
config :forge, :api_server,
  enabled: true,
  port: 4102

# Import environment specific config
import_config "#{config_env()}.exs"
