defmodule Forge.Repo.Migrations.CreateSamples do
  use Ecto.Migration

  def change do
    create table(:forge_samples, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:pipeline_id, references(:forge_pipelines, type: :uuid), null: false)
      add(:parent_sample_id, references(:forge_samples, type: :uuid))
      add(:version, :integer, default: 1)
      add(:status, :string, null: false, default: "pending")
      add(:data, :map, null: false)
      add(:deleted_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forge_samples, [:pipeline_id, :status]))
    create(index(:forge_samples, [:pipeline_id, :inserted_at]))
    create(index(:forge_samples, [:parent_sample_id], where: "parent_sample_id IS NOT NULL"))
    create(index(:forge_samples, [:id], using: :hash))
  end
end
