defmodule Forge.Measurement do
  @moduledoc """
  Behaviour for computing measurements on samples.

  Measurements are computations performed on batches of samples to extract
  metrics, statistics, or derived values. They can be synchronous (blocking)
  or asynchronous (non-blocking).

  ## Callbacks

    * `compute/1` - Calculate measurements from a list of samples (required)
    * `key/0` - Unique identifier for this measurement (required)
    * `version/0` - Version number for this measurement (required)
    * `async?/0` - Whether to run asynchronously (optional, default: false)
    * `batch_capable?/0` - Whether measurement supports batch processing (optional, default: false)
    * `batch_size/0` - Preferred batch size (optional, required if batch_capable?)
    * `compute_batch/1` - Compute measurements for a batch of samples (optional)
    * `dependencies/0` - List of measurement modules this depends on (optional, default: [])
    * `timeout/0` - Timeout for computation in milliseconds (optional, default: 60_000)

  ## Examples

      defmodule MyMeasurement do
        @behaviour Forge.Measurement

        def key do
          config = %{model: "v1"}
          hash = :crypto.hash(:sha256, :erlang.term_to_binary(config)) |> Base.encode16()
          "my_measurement:\#{hash}"
        end

        def version, do: 1

        def compute(samples) do
          values = Enum.map(samples, & &1.data.value)
          mean = Enum.sum(values) / length(values)
          {:ok, %{mean: mean}}
        end
      end

      defmodule BatchMeasurement do
        @behaviour Forge.Measurement

        def key, do: "batch_measurement:v1"
        def version, do: 1
        def batch_capable?, do: true
        def batch_size, do: 50

        def compute_batch(samples) do
          # Vectorized computation
          Enum.map(samples, fn sample ->
            {sample.id, %{result: compute_for_sample(sample)}}
          end)
        end

        def compute(samples) do
          {:ok, [result]} = compute_batch(samples)
          {:ok, elem(result, 1)}
        end
      end
  """

  @doc """
  Compute measurements from a list of samples.

  Returns `{:ok, measurements_map}` with computed measurements, or
  `{:error, reason}` on failure.

  The measurements map can contain any key-value pairs representing
  computed metrics.
  """
  @callback compute(samples :: [Forge.Schema.Sample.t()]) ::
              {:ok, measurements :: map()} | {:error, reason :: any()}

  @doc """
  Returns a unique key for this measurement.

  The key should include a hash of the configuration to ensure different
  configurations generate different keys.
  """
  @callback key() :: String.t()

  @doc """
  Returns the version number for this measurement.

  Increment when the computation logic changes to invalidate old results.
  """
  @callback version() :: pos_integer()

  @doc """
  Indicates whether this measurement should run asynchronously.

  Asynchronous measurements don't block pipeline completion and are
  executed in separate tasks.

  Defaults to `false` if not implemented.
  """
  @callback async?() :: boolean()

  @doc """
  Indicates whether this measurement supports batch processing.

  Batch-capable measurements can process multiple samples in a single
  operation for better efficiency (e.g., batch API calls).

  Defaults to `false` if not implemented.
  """
  @callback batch_capable?() :: boolean()

  @doc """
  Returns the preferred batch size for batch processing.

  Required if `batch_capable?/0` returns true.
  """
  @callback batch_size() :: pos_integer()

  @doc """
  Compute measurements for a batch of samples.

  Returns a list of `{sample_id, value}` tuples.

  Required if `batch_capable?/0` returns true.
  """
  @callback compute_batch(samples :: [Forge.Schema.Sample.t()]) ::
              {:ok, [{sample_id :: binary(), value :: map()}]} | {:error, reason :: any()}

  @doc """
  Returns list of measurement modules this measurement depends on.

  Dependencies will be computed before this measurement.

  Defaults to `[]` if not implemented.
  """
  @callback dependencies() :: [module()]

  @doc """
  Returns the timeout for computation in milliseconds.

  Defaults to 60_000 (60 seconds) if not implemented.
  """
  @callback timeout() :: pos_integer()

  @optional_callbacks [
    async?: 0,
    batch_capable?: 0,
    batch_size: 0,
    compute_batch: 1,
    dependencies: 0,
    timeout: 0
  ]

  @doc """
  Returns whether the given measurement module should run asynchronously.
  """
  def async?(module) do
    if function_exported?(module, :async?, 0) do
      module.async?()
    else
      false
    end
  end

  @doc """
  Returns whether the given measurement module supports batch processing.
  """
  def batch_capable?(module) do
    if function_exported?(module, :batch_capable?, 0) do
      module.batch_capable?()
    else
      false
    end
  end

  @doc """
  Returns the batch size for the given measurement module.
  """
  def batch_size(module) do
    if function_exported?(module, :batch_size, 0) do
      module.batch_size()
    else
      1
    end
  end

  @doc """
  Returns the dependencies for the given measurement module.
  """
  def dependencies(module) do
    if function_exported?(module, :dependencies, 0) do
      module.dependencies()
    else
      []
    end
  end

  @doc """
  Returns the timeout for the given measurement module.
  """
  def timeout(module) do
    if function_exported?(module, :timeout, 0) do
      module.timeout()
    else
      60_000
    end
  end
end
