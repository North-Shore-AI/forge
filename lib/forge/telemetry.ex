defmodule Forge.Telemetry do
  @moduledoc """
  Telemetry instrumentation for Forge pipelines.

  This module provides helper functions for emitting structured telemetry events
  throughout pipeline execution. All events follow the naming convention:
  `[:forge, :component, :action]`

  ## Event Categories

  ### Pipeline Events

  - `[:forge, :pipeline, :start]` - Pipeline execution started
  - `[:forge, :pipeline, :stop]` - Pipeline execution completed
  - `[:forge, :pipeline, :exception]` - Pipeline execution failed with exception

  ### Stage Events

  - `[:forge, :stage, :start]` - Stage processing started for a sample
  - `[:forge, :stage, :stop]` - Stage processing completed (success or error)
  - `[:forge, :stage, :retry]` - Stage retry attempt

  ### Measurement Events

  - `[:forge, :measurement, :start]` - Measurement computation started
  - `[:forge, :measurement, :stop]` - Measurement computation completed
  - `[:forge, :measurement, :batch_complete]` - Batch measurement completed

  ### Storage Events

  - `[:forge, :storage, :sample_write]` - Sample written to storage
  - `[:forge, :storage, :artifact_upload]` - Artifact uploaded
  - `[:forge, :storage, :artifact_download]` - Artifact downloaded

  ### DLQ Events

  - `[:forge, :dlq, :enqueue]` - Sample moved to dead-letter queue

  ## Usage

      # Emit events directly
      Telemetry.pipeline_start(pipeline_id, run_id, :my_pipeline)

      # Or use the span helper for automatic timing
      Telemetry.span([:forge, :stage], %{stage: "MyStage"}, fn ->
        # ... processing logic
        {:ok, result}
      end)

  ## Attaching Handlers

      :telemetry.attach(
        "my-handler",
        [:forge, :pipeline, :start],
        fn event, measurements, metadata, config ->
          # Handle event
        end,
        nil
      )
  """

  @doc """
  Emits a pipeline start event.

  ## Measurements

  - `:system_time` - System time when pipeline started (native units)

  ## Metadata

  - `:pipeline_id` - Unique identifier for the pipeline definition
  - `:run_id` - Unique identifier for this execution run
  - `:name` - Pipeline name (atom or string)
  """
  def pipeline_start(pipeline_id, run_id, name) do
    :telemetry.execute(
      [:forge, :pipeline, :start],
      %{system_time: System.system_time()},
      %{pipeline_id: pipeline_id, run_id: run_id, name: name}
    )
  end

  @doc """
  Emits a pipeline stop event.

  ## Measurements

  - `:duration` - Duration in native time units
  - `:samples_processed` - Number of samples successfully processed

  ## Metadata

  - `:pipeline_id` - Unique identifier for the pipeline definition
  - `:run_id` - Unique identifier for this execution run
  - `:outcome` - `:completed` or `:failed`
  """
  def pipeline_stop(pipeline_id, run_id, duration, outcome, samples_processed \\ 0) do
    :telemetry.execute(
      [:forge, :pipeline, :stop],
      %{duration: duration, samples_processed: samples_processed},
      %{pipeline_id: pipeline_id, run_id: run_id, outcome: outcome}
    )
  end

  @doc """
  Emits a pipeline exception event.

  ## Measurements

  - `:duration` - Duration before exception (native time units)

  ## Metadata

  - `:pipeline_id` - Unique identifier for the pipeline definition
  - `:run_id` - Unique identifier for this execution run
  - `:exception` - Exception module (e.g., `RuntimeError`)
  """
  def pipeline_exception(pipeline_id, run_id, duration, exception) do
    :telemetry.execute(
      [:forge, :pipeline, :exception],
      %{duration: duration},
      %{pipeline_id: pipeline_id, run_id: run_id, exception: exception}
    )
  end

  @doc """
  Emits a stage start event.

  ## Measurements

  - `:system_time` - System time when stage started (native units)

  ## Metadata

  - `:sample_id` - ID of the sample being processed
  - `:stage` - Stage module name or identifier
  - `:pipeline_id` - Pipeline identifier (optional)
  - `:run_id` - Run identifier (optional)
  """
  def stage_start(sample_id, stage, pipeline_id \\ nil, run_id \\ nil) do
    metadata = %{sample_id: sample_id, stage: stage}

    metadata =
      if pipeline_id, do: Map.put(metadata, :pipeline_id, pipeline_id), else: metadata

    metadata = if run_id, do: Map.put(metadata, :run_id, run_id), else: metadata

    :telemetry.execute(
      [:forge, :stage, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a stage stop event.

  ## Measurements

  - `:duration` - Duration in native time units

  ## Metadata

  - `:sample_id` - ID of the sample being processed
  - `:stage` - Stage module name or identifier
  - `:outcome` - `:success`, `:error`, or `:skip`
  - `:error_type` - Error classification (optional, only for errors)
  """
  def stage_stop(sample_id, stage, duration, outcome, error_type \\ nil) do
    metadata = %{
      sample_id: sample_id,
      stage: stage,
      outcome: outcome
    }

    metadata = if error_type, do: Map.put(metadata, :error_type, error_type), else: metadata

    :telemetry.execute(
      [:forge, :stage, :stop],
      %{duration: duration},
      metadata
    )
  end

  @doc """
  Emits a stage retry event.

  ## Measurements

  - `:attempt` - Attempt number (1-based)
  - `:delay_ms` - Delay before next retry in milliseconds

  ## Metadata

  - `:sample_id` - ID of the sample being processed
  - `:stage` - Stage module name or identifier
  - `:error` - Error reason or message
  """
  def stage_retry(sample_id, stage, attempt, delay_ms, error) do
    :telemetry.execute(
      [:forge, :stage, :retry],
      %{attempt: attempt, delay_ms: delay_ms},
      %{sample_id: sample_id, stage: stage, error: error}
    )
  end

  @doc """
  Emits a measurement start event.

  ## Measurements

  - `:system_time` - System time when measurement started (native units)

  ## Metadata

  - `:sample_id` - ID of the sample being measured
  - `:measurement_key` - Measurement key/name
  - `:version` - Measurement version
  """
  def measurement_start(sample_id, measurement_key, version) do
    :telemetry.execute(
      [:forge, :measurement, :start],
      %{system_time: System.system_time()},
      %{sample_id: sample_id, measurement_key: measurement_key, version: version}
    )
  end

  @doc """
  Emits a measurement stop event.

  ## Measurements

  - `:duration` - Duration in native time units

  ## Metadata

  - `:sample_id` - ID of the sample being measured
  - `:measurement_key` - Measurement key/name
  - `:outcome` - `:computed` or `:cached`
  """
  def measurement_stop(sample_id, measurement_key, duration, outcome) do
    :telemetry.execute(
      [:forge, :measurement, :stop],
      %{duration: duration},
      %{sample_id: sample_id, measurement_key: measurement_key, outcome: outcome}
    )
  end

  @doc """
  Emits a batch measurement complete event.

  ## Measurements

  - `:duration` - Duration in native time units
  - `:batch_size` - Number of samples in batch

  ## Metadata

  - `:measurement_key` - Measurement key/name
  """
  def measurement_batch_complete(measurement_key, duration, batch_size) do
    :telemetry.execute(
      [:forge, :measurement, :batch_complete],
      %{duration: duration, batch_size: batch_size},
      %{measurement_key: measurement_key}
    )
  end

  @doc """
  Emits a storage sample write event.

  ## Measurements

  - `:duration` - Duration in native time units
  - `:size_bytes` - Size of data written in bytes

  ## Metadata

  - `:sample_id` - ID of the sample being stored
  - `:storage_backend` - Storage backend identifier (e.g., `:postgres`, `:ets`)
  """
  def storage_sample_write(sample_id, duration, size_bytes, storage_backend) do
    :telemetry.execute(
      [:forge, :storage, :sample_write],
      %{duration: duration, size_bytes: size_bytes},
      %{sample_id: sample_id, storage_backend: storage_backend}
    )
  end

  @doc """
  Emits a storage artifact upload event.

  ## Measurements

  - `:duration` - Duration in native time units
  - `:size_bytes` - Size of artifact in bytes

  ## Metadata

  - `:artifact_key` - Artifact key/path
  - `:deduplication` - Whether deduplication was used (boolean)
  """
  def storage_artifact_upload(artifact_key, duration, size_bytes, deduplication) do
    :telemetry.execute(
      [:forge, :storage, :artifact_upload],
      %{duration: duration, size_bytes: size_bytes},
      %{artifact_key: artifact_key, deduplication: deduplication}
    )
  end

  @doc """
  Emits a storage artifact download event.

  ## Measurements

  - `:duration` - Duration in native time units
  - `:size_bytes` - Size of artifact in bytes

  ## Metadata

  - `:artifact_key` - Artifact key/path
  """
  def storage_artifact_download(artifact_key, duration, size_bytes) do
    :telemetry.execute(
      [:forge, :storage, :artifact_download],
      %{duration: duration, size_bytes: size_bytes},
      %{artifact_key: artifact_key}
    )
  end

  @doc """
  Emits a DLQ enqueue event.

  ## Measurements

  (empty map)

  ## Metadata

  - `:sample_id` - ID of the sample being moved to DLQ
  - `:stage` - Stage where failure occurred
  - `:error` - Error reason or message
  """
  def dlq_enqueue(sample_id, stage, error) do
    :telemetry.execute(
      [:forge, :dlq, :enqueue],
      %{},
      %{sample_id: sample_id, stage: stage, error: error}
    )
  end

  @doc """
  Executes a function and emits telemetry span events.

  This is a convenience function for wrapping operations with automatic
  start/stop timing. It emits:

  - `event ++ [:start]` before execution
  - `event ++ [:stop]` after successful execution
  - `event ++ [:exception]` if an exception is raised

  ## Parameters

  - `event` - Base event name (e.g., `[:forge, :stage]`)
  - `metadata` - Metadata to include in all events
  - `fun` - Function to execute

  ## Returns

  The return value of the function.

  ## Examples

      result = Telemetry.span([:forge, :stage], %{stage: "MyStage"}, fn ->
        # ... processing logic
        {:ok, processed_sample}
      end)
  """
  def span(event, metadata, fun)
      when is_list(event) and is_map(metadata) and is_function(fun, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      event ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        event ++ [:stop],
        %{duration: duration},
        metadata
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          event ++ [:exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e})
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Attaches telemetry handlers for logging and metrics aggregation.

  This function should be called once during application startup to attach
  handlers that will process telemetry events.

  ## Options

  - `:reporters` - List of reporter modules to attach (default: `[]`)
  """
  def attach_handlers(opts \\ []) do
    reporters = Keyword.get(opts, :reporters, [])

    Enum.each(reporters, fn reporter ->
      if function_exported?(reporter, :attach, 0) do
        reporter.attach()
      end
    end)

    :ok
  end
end
