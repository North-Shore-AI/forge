import Config

config :forge, Forge.Repo,
  database: "forge_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :forge, :start_repo, true
config :forge, :api_server, enabled: false

config :logger, level: :warning
