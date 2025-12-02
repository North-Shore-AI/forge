defmodule Forge.Repo.Migrations.AddManifestHashToSamples do
  use Ecto.Migration

  def change do
    alter table(:forge_samples) do
      add(:manifest_hash, :string)
    end

    create(index(:forge_samples, [:manifest_hash]))
  end
end
