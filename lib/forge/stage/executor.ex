defmodule Forge.Stage.Executor do
  @moduledoc """
  Executes stages with retry logic and error handling.

  Implements the retry strategy defined in ADR-003, including:
  - Per-stage retry policies
  - Exponential backoff with jitter
  - Error classification (retriable vs non-retriable)
  - Dead-letter queue integration

  ## Usage

      alias Forge.Stage.Executor

      sample = Forge.Sample.new(id: "123", pipeline: :test, data: %{value: 42})

      case Executor.apply_with_retry(sample, MyStage) do
        {:ok, processed_sample} ->
          # Stage succeeded

        {:error, :max_retries, reason} ->
          # Stage failed after max attempts, send to DLQ
      end
  """

  require Logger

  alias Forge.{RetryPolicy, ErrorClassifier}

  @doc """
  Applies a stage to a sample with retry logic.

  Returns:
    * `{:ok, sample}` - Stage succeeded
    * `{:skip, reason}` - Sample was filtered by stage
    * `{:error, :max_retries, reason}` - Stage failed after max attempts

  The function will:
  1. Get the retry policy from the stage (or use default)
  2. Attempt to process the sample
  3. On error, classify if it's retriable
  4. If retriable and attempts remain, wait and retry
  5. If non-retriable or max attempts reached, return error
  """
  def apply_with_retry(sample, stage_module) do
    policy = get_retry_policy(stage_module)

    Enum.reduce_while(1..policy.max_attempts, {:error, :no_attempts}, fn attempt, _acc ->
      case apply_stage(sample, stage_module) do
        {:ok, result} ->
          if attempt > 1 do
            Logger.info(
              "Stage #{stage_name(stage_module)} succeeded on attempt #{attempt} for sample #{sample.id}"
            )
          end

          {:halt, {:ok, result}}

        {:skip, _reason} = skip_result ->
          # Skip is not an error, halt immediately
          {:halt, skip_result}

        {:error, error} = err ->
          if ErrorClassifier.retriable?(error, policy) and attempt < policy.max_attempts do
            # Retriable error with attempts remaining
            delay = RetryPolicy.compute_delay(attempt, policy)

            Logger.warning(
              "Stage #{stage_name(stage_module)} failed on attempt #{attempt}/#{policy.max_attempts} " <>
                "for sample #{sample.id}: #{inspect(error)}. Retrying in #{delay}ms"
            )

            # Use Process.sleep for delay (tests can override with smaller delays)
            Process.sleep(delay)

            {:cont, err}
          else
            # Non-retriable or exhausted attempts
            if attempt >= policy.max_attempts do
              Logger.error(
                "Stage #{stage_name(stage_module)} failed after #{policy.max_attempts} attempts " <>
                  "for sample #{sample.id}: #{inspect(error)}"
              )
            else
              Logger.error(
                "Stage #{stage_name(stage_module)} failed with non-retriable error " <>
                  "for sample #{sample.id}: #{inspect(error)}"
              )
            end

            {:halt, {:error, :max_retries, error}}
          end
      end
    end)
  end

  @doc """
  Gets the retry policy for a stage.

  If the stage implements `retry_policy/0`, uses that. Otherwise, returns
  the default policy.
  """
  def get_retry_policy(stage_module) do
    if function_exported?(stage_module, :retry_policy, 0) do
      stage_module.retry_policy()
    else
      RetryPolicy.default()
    end
  end

  # Private helpers

  defp apply_stage(sample, stage_module) do
    stage_module.process(sample)
  end

  defp stage_name(stage_module) do
    stage_module
    |> Module.split()
    |> List.last()
  end
end
