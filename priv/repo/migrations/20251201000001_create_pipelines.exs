defmodule Forge.Repo.Migrations.CreatePipelines do
  use Ecto.Migration

  def change do
    create table(:forge_pipelines, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, null: false)
      add(:manifest_hash, :string, null: false)
      add(:manifest, :map, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:deleted_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forge_pipelines, [:name, :inserted_at]))
    create(index(:forge_pipelines, [:manifest_hash]))
    create(index(:forge_pipelines, [:status], where: "deleted_at IS NULL"))
  end
end
