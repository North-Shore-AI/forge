defmodule Forge.Repo do
  @moduledoc """
  Ecto repository for Forge persistence layer.

  Provides database access for pipelines, samples, measurements, and artifacts.
  """

  use Ecto.Repo,
    otp_app: :forge,
    adapter: Ecto.Adapters.Postgres
end
