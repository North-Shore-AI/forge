defmodule Forge.Schema.RunManifest do
  @moduledoc """
  Ecto schema for storing pipeline run manifests.

  Captures the complete configuration and metadata for a pipeline run,
  enabling reproducibility and lineage tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "forge_run_manifests" do
    field(:run_id, :string)
    field(:pipeline_name, :string)
    field(:manifest, :map)
    field(:manifest_hash, :string)
    field(:sample_count, :integer)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(run_manifest, attrs) do
    run_manifest
    |> cast(attrs, [
      :run_id,
      :pipeline_name,
      :manifest,
      :manifest_hash,
      :sample_count,
      :started_at,
      :completed_at
    ])
    |> validate_required([:run_id, :pipeline_name, :manifest, :manifest_hash])
    |> unique_constraint(:run_id)
  end
end
