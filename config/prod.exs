import Config

# Production configuration
# Configure your database from environment variables
config :forge, Forge.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true
