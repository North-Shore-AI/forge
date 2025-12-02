defmodule Forge.Measurement do
  @moduledoc """
  Behaviour for computing measurements on samples.

  Measurements are computations performed on batches of samples to extract
  metrics, statistics, or derived values. They can be synchronous (blocking)
  or asynchronous (non-blocking).

  ## Callbacks

    * `compute/1` - Calculate measurements from a list of samples (required)
    * `async?/0` - Whether to run asynchronously (optional, default: false)

  ## Examples

      defmodule MeanMeasurement do
        @behaviour Forge.Measurement

        def compute(samples) do
          values = Enum.map(samples, & &1.data.value)
          mean = Enum.sum(values) / length(values)
          {:ok, %{mean: mean}}
        end

        def async?(), do: false
      end

      defmodule ExpensiveMeasurement do
        @behaviour Forge.Measurement

        def compute(samples) do
          result = perform_complex_analysis(samples)
          {:ok, %{analysis: result}}
        end

        def async?(), do: true  # Run in background
      end
  """

  @doc """
  Compute measurements from a list of samples.

  Returns `{:ok, measurements_map}` with computed measurements, or
  `{:error, reason}` on failure.

  The measurements map can contain any key-value pairs representing
  computed metrics.
  """
  @callback compute(samples :: [Forge.Sample.t()]) ::
              {:ok, measurements :: map()} | {:error, reason :: any()}

  @doc """
  Indicates whether this measurement should run asynchronously.

  Asynchronous measurements don't block pipeline completion and are
  executed in separate tasks.

  Defaults to `false` if not implemented.
  """
  @callback async?() :: boolean()

  @optional_callbacks [async?: 0]

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
end
