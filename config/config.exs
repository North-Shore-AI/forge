import Config

config :forge, Forge.Repo,
  database: "forge_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :forge, ecto_repos: [Forge.Repo]

# Import environment specific config
import_config "#{config_env()}.exs"
