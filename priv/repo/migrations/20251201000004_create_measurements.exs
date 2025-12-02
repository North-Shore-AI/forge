defmodule Forge.Repo.Migrations.CreateMeasurements do
  use Ecto.Migration

  def change do
    create table(:forge_measurements, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(:sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:measurement_key, :string, null: false)
      add(:measurement_version, :integer, default: 1)
      add(:value, :map, null: false)
      add(:computed_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:forge_measurements, [:sample_id, :measurement_key, :measurement_version])
    )

    create(index(:forge_measurements, [:measurement_key]))
  end
end
