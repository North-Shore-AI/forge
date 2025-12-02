defmodule Forge.AnvilBridge.Mock do
  @moduledoc """
  Mock adapter for AnvilBridge used in testing.

  Maintains in-memory state for published samples and labels.
  Provides deterministic behavior for testing without requiring Anvil.
  """

  @behaviour Forge.AnvilBridge

  use Agent

  @doc """
  Start the mock adapter agent.

  This is typically called automatically in test setup.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @doc """
  Reset the mock adapter state.

  Useful for test isolation.
  """
  def reset do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> initial_state() end)
    else
      start_link()
    end
  end

  @doc """
  Get the current state of the mock adapter.

  Useful for test assertions.
  """
  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  @impl true
  def publish_sample(sample, opts) do
    queue = Keyword.fetch!(opts, :queue)
    include_measurements = Keyword.get(opts, :include_measurements, true)

    dto = Forge.AnvilBridge.sample_to_dto(sample, include_measurements: include_measurements)
    job_id = generate_job_id()

    Agent.update(__MODULE__, fn state ->
      job = Map.put(dto, :job_id, job_id)
      updated_jobs = [job | state.jobs]
      updated_queues = Map.update(state.queues, queue, [job], fn jobs -> [job | jobs] end)

      %{state | jobs: updated_jobs, queues: updated_queues}
    end)

    {:ok, job_id}
  rescue
    ArgumentError -> {:error, :not_started}
  end

  @impl true
  def publish_batch(samples, opts) do
    queue = Keyword.fetch!(opts, :queue)
    include_measurements = Keyword.get(opts, :include_measurements, true)

    jobs =
      Enum.map(samples, fn sample ->
        dto = Forge.AnvilBridge.sample_to_dto(sample, include_measurements: include_measurements)
        Map.put(dto, :job_id, generate_job_id())
      end)

    Agent.update(__MODULE__, fn state ->
      updated_jobs = jobs ++ state.jobs
      updated_queues = Map.update(state.queues, queue, jobs, fn existing -> jobs ++ existing end)

      %{state | jobs: updated_jobs, queues: updated_queues}
    end)

    {:ok, length(jobs)}
  rescue
    ArgumentError -> {:error, :not_started}
  end

  @impl true
  def get_labels(sample_id) do
    labels =
      Agent.get(__MODULE__, fn state ->
        Map.get(state.labels, sample_id, [])
      end)

    if Enum.empty?(labels) do
      {:error, :not_found}
    else
      {:ok, labels}
    end
  rescue
    ArgumentError -> {:error, :not_started}
  end

  @impl true
  def sync_labels(sample_id, _opts \\ []) do
    case get_labels(sample_id) do
      {:ok, labels} ->
        {:ok, length(labels)}

      {:error, :not_found} ->
        {:ok, 0}

      error ->
        error
    end
  end

  @impl true
  def create_queue_for_pipeline(pipeline_id, opts) do
    queue_name = Keyword.get(opts, :queue_name, pipeline_id)
    description = Keyword.get(opts, :description, "Queue for pipeline #{pipeline_id}")
    priority = Keyword.get(opts, :priority, "normal")

    Agent.update(__MODULE__, fn state ->
      queue_info = %{
        name: queue_name,
        pipeline_id: pipeline_id,
        description: description,
        priority: priority,
        created_at: DateTime.utc_now()
      }

      updated_queue_metadata = Map.put(state.queue_metadata, queue_name, queue_info)
      %{state | queue_metadata: updated_queue_metadata}
    end)

    {:ok, queue_name}
  rescue
    ArgumentError -> {:error, :not_started}
  end

  @impl true
  def get_queue_stats(queue_name) do
    stats =
      Agent.get(__MODULE__, fn state ->
        jobs = Map.get(state.queues, queue_name, [])

        %{
          total: length(jobs),
          completed: Enum.count(jobs, fn job -> Map.get(job, :completed, false) end),
          pending: Enum.count(jobs, fn job -> !Map.get(job, :in_progress, false) end),
          in_progress: Enum.count(jobs, fn job -> Map.get(job, :in_progress, false) end)
        }
      end)

    {:ok, stats}
  rescue
    ArgumentError -> {:error, :not_started}
  end

  # Mock-specific helpers

  @doc """
  Add mock labels for a sample.

  Useful for testing label retrieval and sync.
  """
  def add_labels(sample_id, labels) when is_list(labels) do
    Agent.update(__MODULE__, fn state ->
      updated_labels = Map.put(state.labels, sample_id, labels)
      %{state | labels: updated_labels}
    end)
  end

  @doc """
  Mark a job as completed.

  Useful for testing queue statistics.
  """
  def complete_job(job_id) do
    Agent.update(__MODULE__, fn state ->
      updated_jobs =
        Enum.map(state.jobs, fn job ->
          if job[:job_id] == job_id do
            Map.put(job, :completed, true)
          else
            job
          end
        end)

      updated_queues =
        Map.new(state.queues, fn {queue_name, jobs} ->
          updated_queue_jobs =
            Enum.map(jobs, fn job ->
              if job[:job_id] == job_id do
                Map.put(job, :completed, true)
              else
                job
              end
            end)

          {queue_name, updated_queue_jobs}
        end)

      %{state | jobs: updated_jobs, queues: updated_queues}
    end)
  end

  # Private helpers

  defp initial_state do
    %{
      jobs: [],
      queues: %{},
      labels: %{},
      queue_metadata: %{}
    }
  end

  defp generate_job_id do
    "job-#{System.unique_integer([:positive, :monotonic])}"
  end
end
