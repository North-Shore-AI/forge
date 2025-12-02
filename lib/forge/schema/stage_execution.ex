defmodule Forge.Schema.StageExecution do
  @moduledoc """
  Ecto schema for stage execution history.

  Tracks which stages have been applied to samples, including status and timing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forge_stages_applied" do
    field(:stage_name, :string)
    field(:stage_config_hash, :string)
    field(:attempt, :integer, default: 1)
    field(:status, :string, default: "success")
    field(:error_message, :string)
    field(:duration_ms, :integer)
    field(:applied_at, :utc_datetime_usec)

    belongs_to(:sample, Forge.Schema.Sample)
  end

  @doc false
  def changeset(stage_execution, attrs) do
    stage_execution
    |> cast(attrs, [
      :sample_id,
      :stage_name,
      :stage_config_hash,
      :attempt,
      :status,
      :error_message,
      :duration_ms,
      :applied_at
    ])
    |> validate_required([:sample_id, :stage_name, :stage_config_hash, :status, :applied_at])
    |> validate_inclusion(:status, ["success", "failed", "retrying"])
    |> foreign_key_constraint(:sample_id)
  end
end
