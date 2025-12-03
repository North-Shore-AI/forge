defmodule Forge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers before starting supervision tree
    attach_telemetry_handlers()

    children =
      []
      |> maybe_child(Application.get_env(:forge, :start_repo, true), Forge.Repo)
      |> maybe_child(true, {Task.Supervisor, name: Forge.MeasurementTaskSupervisor})
      |> maybe_child(api_enabled?(), Forge.API.Server)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Forge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_child(children, true, child), do: children ++ [child]
  defp maybe_child(children, _flag, _child), do: children

  defp api_enabled? do
    config = Application.get_env(:forge, :api_server, [])
    Keyword.get(config, :enabled, false)
  end

  defp attach_telemetry_handlers do
    # Get configured reporters from application env
    reporters = Application.get_env(:forge, :telemetry, [])[:reporters] || []

    # Attach handlers using Forge.Telemetry
    Forge.Telemetry.attach_handlers(reporters: reporters)
  end
end
