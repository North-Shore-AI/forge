defmodule Forge.Measurement.ExternalCompute do
  @moduledoc """
  Behaviour for external compute backends (ALTAR, Snakepit, etc.).

  External compute backends allow offloading measurement computation to
  specialized systems:

  - ALTAR: Python Celery workers for TDA, ML inference
  - Snakepit: LLM workers for semantic analysis, quality scoring

  ## Callbacks

    * `submit_task/2` - Submit a computation task
    * `await_result/2` - Poll for task completion
    * `cancel_task/1` - Cancel a running task

  ## Example Implementation

      defmodule MyBackend do
        @behaviour Forge.Measurement.ExternalCompute

        def submit_task(task_name, params) do
          # Submit to backend
          {:ok, "task-uuid-123"}
        end

        def await_result(task_id, opts) do
          # Poll for result
          {:ok, %{result: "computed"}}
        end

        def cancel_task(task_id) do
          :ok
        end
      end
  """

  @doc """
  Submits a computation task to the external backend.

  Returns `{:ok, task_id}` or `{:error, reason}`.
  """
  @callback submit_task(task_name :: String.t(), params :: map()) ::
              {:ok, task_id :: String.t()} | {:error, reason :: any()}

  @doc """
  Waits for task completion and retrieves the result.

  Options:
  - `:timeout` - Maximum wait time in milliseconds (default: 30_000)
  - `:poll_interval` - How often to check status in milliseconds (default: 1_000)

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @callback await_result(task_id :: String.t(), opts :: keyword()) ::
              {:ok, result :: any()} | {:error, reason :: any()}

  @doc """
  Cancels a running task.

  Returns `:ok` or `{:error, reason}`.
  """
  @callback cancel_task(task_id :: String.t()) :: :ok | {:error, reason :: any()}
end
