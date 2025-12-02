defmodule Forge.Repo.Migrations.CreateRunManifests do
  use Ecto.Migration

  def change do
    create table(:forge_run_manifests, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:run_id, :string, null: false)
      add(:pipeline_name, :string, null: false)
      add(:manifest, :map, null: false)
      add(:manifest_hash, :string, null: false)
      add(:sample_count, :integer)
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:forge_run_manifests, [:run_id]))
    create(index(:forge_run_manifests, [:pipeline_name]))
    create(index(:forge_run_manifests, [:manifest_hash]))
    create(index(:forge_run_manifests, [:started_at]))
  end
end
