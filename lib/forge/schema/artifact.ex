defmodule Forge.Schema.Artifact do
  @moduledoc """
  Ecto schema for artifact metadata.

  Stores pointers to large blobs in external storage (S3, local filesystem).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          artifact_key: String.t() | nil,
          storage_uri: String.t() | nil,
          content_hash: String.t() | nil,
          size_bytes: integer() | nil,
          content_type: String.t() | nil,
          sample_id: binary() | nil,
          sample: Forge.Schema.Sample.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forge_artifacts" do
    field(:artifact_key, :string)
    field(:storage_uri, :string)
    field(:content_hash, :string)
    field(:size_bytes, :integer)
    field(:content_type, :string)

    belongs_to(:sample, Forge.Schema.Sample)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :sample_id,
      :artifact_key,
      :storage_uri,
      :content_hash,
      :size_bytes,
      :content_type
    ])
    |> validate_required([:sample_id, :artifact_key, :storage_uri, :content_hash])
    |> foreign_key_constraint(:sample_id)
    |> unique_constraint([:sample_id, :artifact_key])
  end
end
