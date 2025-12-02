defmodule Forge.Schema.Sample do
  @moduledoc """
  Ecto schema for sample records.

  Stores sample data, status, and tracks lineage through parent relationships.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forge_samples" do
    field(:version, :integer, default: 1)
    field(:status, :string, default: "pending")
    field(:data, :map)
    field(:manifest_hash, :string)
    field(:deleted_at, :utc_datetime_usec)

    belongs_to(:pipeline, Forge.Schema.Pipeline)
    belongs_to(:parent_sample, Forge.Schema.Sample, foreign_key: :parent_sample_id)

    has_many(:child_samples, Forge.Schema.Sample, foreign_key: :parent_sample_id)
    has_many(:stage_executions, Forge.Schema.StageExecution)
    has_many(:measurements, Forge.Schema.MeasurementRecord)
    has_many(:artifacts, Forge.Schema.Artifact)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(sample, attrs) do
    sample
    |> cast(attrs, [
      :pipeline_id,
      :parent_sample_id,
      :version,
      :status,
      :data,
      :manifest_hash,
      :deleted_at
    ])
    |> validate_required([:pipeline_id, :status, :data])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed", "dlq"])
    |> foreign_key_constraint(:pipeline_id)
    |> foreign_key_constraint(:parent_sample_id)
  end
end
