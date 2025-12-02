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
end
