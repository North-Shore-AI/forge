import Config

# Development configuration
# Configure your database
config :forge, Forge.Repo,
  database: "forge_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
