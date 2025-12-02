defmodule Forge.Sample do
  @moduledoc """
  Core data structure representing a sample in the Forge pipeline.

  A sample flows through the pipeline, undergoing transformations and measurements.
  The sample struct tracks its data, computed measurements, and lifecycle status.
  """

  @type status :: :pending | :measured | :ready | :labeled | :skipped | :dlq

  @type t :: %__MODULE__{
          id: String.t(),
          pipeline: atom(),
          data: map(),
          measurements: map(),
          status: status(),
          created_at: DateTime.t(),
          measured_at: DateTime.t() | nil,
          dlq_reason: map() | nil
        }

  @enforce_keys [:id, :pipeline, :data, :created_at]
  defstruct [
    :id,
    :pipeline,
    :data,
    :created_at,
    measurements: %{},
    status: :pending,
    measured_at: nil,
    dlq_reason: nil
  ]

  @doc """
  Creates a new sample with the given attributes.

  ## Options
    * `:id` - Unique identifier (required)
    * `:pipeline` - Pipeline name (required)
    * `:data` - Sample data map (required)
    * `:status` - Initial status (default: `:pending`)
    * `:measurements` - Initial measurements map (default: `%{}`)
    * `:created_at` - Creation timestamp (default: now)

  ## Examples

      iex> Forge.Sample.new(id: "123", pipeline: :test, data: %{value: 42})
      %Forge.Sample{id: "123", pipeline: :test, data: %{value: 42}, status: :pending}
  """
  def new(opts) do
    id = Keyword.fetch!(opts, :id)
    pipeline = Keyword.fetch!(opts, :pipeline)
    data = Keyword.fetch!(opts, :data)
    status = Keyword.get(opts, :status, :pending)
    measurements = Keyword.get(opts, :measurements, %{})
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())

    %__MODULE__{
      id: id,
      pipeline: pipeline,
      data: data,
      status: status,
      measurements: measurements,
      created_at: created_at
    }
  end

  @doc "Checks if sample is pending"
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(_), do: false

  @doc "Checks if sample has been measured"
  def measured?(%__MODULE__{status: :measured}), do: true
  def measured?(_), do: false

  @doc "Checks if sample is ready"
  def ready?(%__MODULE__{status: :ready}), do: true
  def ready?(_), do: false

  @doc "Checks if sample is labeled"
  def labeled?(%__MODULE__{status: :labeled}), do: true
  def labeled?(_), do: false

  @doc "Checks if sample was skipped"
  def skipped?(%__MODULE__{status: :skipped}), do: true
  def skipped?(_), do: false

  @doc "Marks sample as measured with current timestamp"
  def mark_measured(%__MODULE__{} = sample) do
    %{sample | status: :measured, measured_at: DateTime.utc_now()}
  end

  @doc "Marks sample as ready"
  def mark_ready(%__MODULE__{} = sample) do
    %{sample | status: :ready}
  end

  @doc "Marks sample as labeled"
  def mark_labeled(%__MODULE__{} = sample) do
    %{sample | status: :labeled}
  end

  @doc "Marks sample as skipped"
  def mark_skipped(%__MODULE__{} = sample) do
    %{sample | status: :skipped}
  end

  @doc "Checks if sample is in dead-letter queue"
  def dlq?(%__MODULE__{status: :dlq}), do: true
  def dlq?(_), do: false

  @doc """
  Marks sample for dead-letter queue with reason.

  ## Options
    * `:stage` - Stage name that failed (required)
    * `:error` - Error that caused failure (required)
    * `:attempts` - Number of attempts made (optional)
  """
  def mark_dlq(%__MODULE__{} = sample, reason) when is_map(reason) do
    dlq_reason =
      reason
      |> Map.put_new(:timestamp, DateTime.utc_now())

    %{sample | status: :dlq, dlq_reason: dlq_reason}
  end

  @doc "Adds measurements to the sample"
  def add_measurements(%__MODULE__{} = sample, measurements) when is_map(measurements) do
    %{sample | measurements: Map.merge(sample.measurements, measurements)}
  end

  @doc "Updates sample data"
  def update_data(%__MODULE__{} = sample, data) when is_map(data) do
    %{sample | data: data}
  end

  @doc "Merges data into sample"
  def merge_data(%__MODULE__{} = sample, data) when is_map(data) do
    %{sample | data: Map.merge(sample.data, data)}
  end
end
