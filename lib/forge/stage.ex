defmodule Forge.Stage do
  @moduledoc """
  Behaviour for pipeline stages.

  Stages transform samples as they flow through a pipeline. Each stage processes
  one sample at a time and can:

  - Transform the sample data
  - Filter out samples (skip)
  - Change the sample status
  - Add metadata or measurements
  - Fail with an error

  ## Return Values

    * `{:ok, sample}` - Continue with the transformed sample
    * `{:skip, reason}` - Remove this sample from the pipeline
    * `{:error, reason}` - Stage failed, error handling depends on runner config

  ## Examples

      defmodule NormalizeStage do
        @behaviour Forge.Stage

        def process(sample) do
          normalized = sample.data.value / 100.0
          data = Map.put(sample.data, :normalized, normalized)
          {:ok, %{sample | data: data}}
        end
      end

      defmodule FilterStage do
        @behaviour Forge.Stage

        def process(sample) do
          if sample.data.value > 0 do
            {:ok, sample}
          else
            {:skip, :negative_value}
          end
        end
      end
  """

  @doc """
  Process a single sample.

  The sample is passed through the stage and can be transformed, filtered, or
  cause an error.
  """
  @callback process(sample :: Forge.Sample.t()) ::
              {:ok, Forge.Sample.t()}
              | {:skip, reason :: any()}
              | {:error, reason :: any()}

  @doc """
  Whether this stage should be executed asynchronously.

  Async stages are executed concurrently with backpressure control.
  Useful for I/O-bound stages (LLM calls, embeddings, HTTP APIs).

  Defaults to false (synchronous execution).
  """
  @callback async?() :: boolean()

  @doc """
  Concurrency limit for async stages.

  Limits the number of concurrent executions for this stage.
  Defaults to System.schedulers_online() if not specified.
  """
  @callback concurrency() :: pos_integer()

  @doc """
  Timeout for stage execution in milliseconds.

  Stages exceeding this timeout will be killed.
  Defaults to 30_000 (30 seconds).
  """
  @callback timeout() :: pos_integer()

  @optional_callbacks [async?: 0, concurrency: 0, timeout: 0]

  @doc """
  Helper to check if a stage module supports async execution.
  """
  def async?(stage_module) do
    if function_exported?(stage_module, :async?, 0) do
      stage_module.async?()
    else
      false
    end
  end

  @doc """
  Helper to get stage concurrency setting.
  """
  def concurrency(stage_module) do
    if function_exported?(stage_module, :concurrency, 0) do
      stage_module.concurrency()
    else
      System.schedulers_online()
    end
  end

  @doc """
  Helper to get stage timeout.
  """
  def timeout(stage_module) do
    if function_exported?(stage_module, :timeout, 0) do
      stage_module.timeout()
    else
      30_000
    end
  end
end
