defmodule Forge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers before starting supervision tree
    attach_telemetry_handlers()

    children = [
      Forge.Repo,
      {Task.Supervisor, name: Forge.MeasurementTaskSupervisor}
      # Starts a worker by calling: Forge.Worker.start_link(arg)
      # {Forge.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Forge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp attach_telemetry_handlers do
    # Get configured reporters from application env
    reporters = Application.get_env(:forge, :telemetry, [])[:reporters] || []

    # Attach handlers using Forge.Telemetry
    Forge.Telemetry.attach_handlers(reporters: reporters)
  end
end
