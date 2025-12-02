defmodule Forge.Schema.MeasurementRecord do
  @moduledoc """
  Ecto schema for measurement results.

  Stores computed metrics and features for samples.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          measurement_key: String.t() | nil,
          measurement_version: integer(),
          value: map() | nil,
          computed_at: DateTime.t() | nil,
          sample_id: binary() | nil,
          sample: Forge.Schema.Sample.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forge_measurements" do
    field(:measurement_key, :string)
    field(:measurement_version, :integer, default: 1)
    field(:value, :map)
    field(:computed_at, :utc_datetime_usec)

    belongs_to(:sample, Forge.Schema.Sample)
  end

  @doc false
  def changeset(measurement, attrs) do
    measurement
    |> cast(attrs, [:sample_id, :measurement_key, :measurement_version, :value, :computed_at])
    |> validate_required([:sample_id, :measurement_key, :value, :computed_at])
    |> foreign_key_constraint(:sample_id)
    |> unique_constraint([:sample_id, :measurement_key, :measurement_version])
  end
end
