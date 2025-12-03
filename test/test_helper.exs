ExUnit.start()

# Configure Ecto sandbox for concurrent tests when repo is enabled
if Application.get_env(:forge, :start_repo, true) do
  Ecto.Adapters.SQL.Sandbox.mode(Forge.Repo, :manual)
end

# Load shared test support modules
Code.require_file(Path.join(__DIR__, "support/test_stages.ex"))
