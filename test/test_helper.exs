ExUnit.start()

# Configure Ecto sandbox for concurrent tests
Ecto.Adapters.SQL.Sandbox.mode(Forge.Repo, :manual)

# Load test support files
Code.require_file("support/test_stages.ex", __DIR__)
