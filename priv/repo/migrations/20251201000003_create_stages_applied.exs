defmodule Forge.Repo.Migrations.CreateStagesApplied do
  use Ecto.Migration

  def change do
    create table(:forge_stages_applied) do
      add(:sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:stage_name, :string, null: false)
      add(:stage_config_hash, :string, null: false)
      add(:attempt, :integer, default: 1)
      add(:status, :string, null: false, default: "success")
      add(:error_message, :text)
      add(:duration_ms, :integer)
      add(:applied_at, :utc_datetime_usec, null: false)
    end

    create(index(:forge_stages_applied, [:sample_id, :applied_at]))
    create(index(:forge_stages_applied, [:stage_name, :status]))
  end
end
