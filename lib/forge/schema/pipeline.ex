defmodule Forge.Schema.Pipeline do
  @moduledoc """
  Ecto schema for pipeline definitions.

  Stores pipeline manifests, configuration hashes, and execution status.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          name: String.t() | nil,
          manifest_hash: String.t() | nil,
          manifest: map() | nil,
          status: String.t(),
          deleted_at: DateTime.t() | nil,
          samples: [Forge.Schema.Sample.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forge_pipelines" do
    field(:name, :string)
    field(:manifest_hash, :string)
    field(:manifest, :map)
    field(:status, :string, default: "pending")
    field(:deleted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)

    has_many(:samples, Forge.Schema.Sample)
  end

  @doc false
  def changeset(pipeline, attrs) do
    pipeline
    |> cast(attrs, [:name, :manifest_hash, :manifest, :status, :deleted_at])
    |> validate_required([:name, :manifest_hash, :manifest, :status])
    |> validate_inclusion(:status, ["pending", "running", "completed", "failed"])
  end
end
