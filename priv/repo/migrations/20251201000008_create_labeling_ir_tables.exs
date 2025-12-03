defmodule Forge.Repo.Migrations.CreateLabelingIrTables do
  use Ecto.Migration

  def change do
    create table(:labeling_samples, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:tenant_id, :string, null: false)
      add(:namespace, :string)
      add(:pipeline_id, :string)
      add(:payload, :map, null: false, default: %{})
      add(:artifacts, {:array, :map}, null: false, default: [])
      add(:metadata, :map, null: false, default: %{})
      add(:lineage_ref, :map)
      add(:created_at, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:labeling_samples, [:tenant_id]))
    create(index(:labeling_samples, [:pipeline_id]))

    create table(:labeling_datasets, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:tenant_id, :string, null: false)
      add(:namespace, :string)
      add(:version, :string, null: false)
      add(:slices, {:array, :map}, null: false, default: [])
      add(:source_refs, {:array, :map}, null: false, default: [])
      add(:metadata, :map, null: false, default: %{})
      add(:lineage_ref, :map)
      add(:created_at, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:labeling_datasets, [:tenant_id]))
    create(index(:labeling_datasets, [:version]))
  end
end
