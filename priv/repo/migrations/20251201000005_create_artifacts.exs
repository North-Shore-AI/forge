defmodule Forge.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:forge_artifacts, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(:sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:artifact_key, :string, null: false)
      add(:storage_uri, :string, null: false)
      add(:content_hash, :string, null: false)
      add(:size_bytes, :bigint)
      add(:content_type, :string)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:forge_artifacts, [:sample_id, :artifact_key]))
    create(index(:forge_artifacts, [:sample_id]))
  end
end
