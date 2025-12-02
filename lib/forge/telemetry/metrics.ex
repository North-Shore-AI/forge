defmodule Forge.Telemetry.Metrics do
  @moduledoc """
  Telemetry metrics definitions for Forge pipelines.

  This module defines metric specifications that can be consumed by various
  telemetry reporters (StatsD, Prometheus, etc.) using the TelemetryMetrics
  library pattern.

  ## Metric Categories

  ### Counters
  - Pipeline completions (by outcome)
  - Stage executions (by stage, outcome)
  - Retry attempts (by stage)
  - DLQ enqueues (by stage, error)
  - Measurement cache hits/misses

  ### Distributions (Histograms)
  - Pipeline duration
  - Stage latency (by stage)
  - Measurement computation time
  - Storage operation latency
  - Artifact upload/download sizes

  ## Usage with Reporters

  This module provides metric definitions that can be used with different
  telemetry reporters. Since telemetry_metrics is an optional dependency,
  these are provided as plain maps that reporters can adapt.

  ### Example: Custom Reporter

      defmodule MyApp.TelemetryReporter do
        def attach do
          metrics = Forge.Telemetry.Metrics.metrics()

          Enum.each(metrics, fn metric ->
            :telemetry.attach(
              "my-reporter-\#{metric.name}",
              metric.event_name,
              &handle_event/4,
              metric
            )
          end)
        end

        defp handle_event(event, measurements, metadata, metric) do
          # Report to your monitoring system
        end
      end

  ### Example: StatsD Reporter

      defmodule Forge.Telemetry.StatsDReporter do
        def attach do
          metrics = Forge.Telemetry.Metrics.metrics()

          Enum.each(metrics, fn metric ->
            case metric.type do
              :counter ->
                :telemetry.attach(...)

              :distribution ->
                :telemetry.attach(...)
            end
          end)
        end
      end
  """

  @doc """
  Returns a list of metric definitions.

  Each metric is a map with:
  - `:type` - `:counter` or `:distribution`
  - `:name` - Metric name
  - `:event_name` - Telemetry event to listen to
  - `:measurement` - Measurement key to extract
  - `:tags` - List of metadata keys to use as tags
  - `:unit` (distributions only) - Unit of measurement
  - `:buckets` (distributions only) - Histogram bucket boundaries
  """
  def metrics do
    [
      # Pipeline Counters
      %{
        type: :counter,
        name: [:forge, :pipeline, :completed],
        event_name: [:forge, :pipeline, :stop],
        measurement: :samples_processed,
        tags: [:outcome],
        description: "Total number of pipeline runs completed"
      },
      %{
        type: :counter,
        name: [:forge, :pipeline, :exceptions],
        event_name: [:forge, :pipeline, :exception],
        measurement: :duration,
        tags: [:exception],
        description: "Total number of pipeline exceptions"
      },

      # Pipeline Distributions
      %{
        type: :distribution,
        name: [:forge, :pipeline, :duration],
        event_name: [:forge, :pipeline, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:pipeline_id, :outcome],
        buckets: [100, 1_000, 10_000, 60_000, 300_000, 600_000],
        description: "Pipeline execution duration in milliseconds"
      },

      # Stage Counters
      %{
        type: :counter,
        name: [:forge, :stage, :executions],
        event_name: [:forge, :stage, :stop],
        measurement: :duration,
        tags: [:stage, :outcome],
        description: "Total number of stage executions"
      },
      %{
        type: :counter,
        name: [:forge, :stage, :retries],
        event_name: [:forge, :stage, :retry],
        measurement: :attempt,
        tags: [:stage],
        description: "Total number of stage retry attempts"
      },

      # Stage Distributions
      %{
        type: :distribution,
        name: [:forge, :stage, :latency],
        event_name: [:forge, :stage, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:stage, :outcome],
        buckets: [10, 50, 100, 500, 1_000, 5_000, 30_000],
        description: "Stage execution latency in milliseconds"
      },

      # Measurement Counters
      %{
        type: :counter,
        name: [:forge, :measurement, :computed],
        event_name: [:forge, :measurement, :stop],
        measurement: :duration,
        tags: [:measurement_key, :outcome],
        description: "Total number of measurements computed"
      },
      %{
        type: :counter,
        name: [:forge, :measurement, :cache_hits],
        event_name: [:forge, :measurement, :stop],
        measurement: :duration,
        tags: [:measurement_key],
        tag_values: fn metadata ->
          if metadata.outcome == :cached do
            Map.put(metadata, :hit, true)
          else
            nil
          end
        end,
        description: "Total number of measurement cache hits"
      },

      # Measurement Distributions
      %{
        type: :distribution,
        name: [:forge, :measurement, :latency],
        event_name: [:forge, :measurement, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:measurement_key],
        buckets: [10, 50, 100, 500, 1_000, 5_000, 30_000],
        description: "Measurement computation latency in milliseconds"
      },
      %{
        type: :distribution,
        name: [:forge, :measurement, :batch_size],
        event_name: [:forge, :measurement, :batch_complete],
        measurement: :batch_size,
        unit: :unit,
        tags: [:measurement_key],
        buckets: [10, 50, 100, 500, 1_000, 5_000],
        description: "Batch measurement sample count"
      },

      # Storage Counters
      %{
        type: :counter,
        name: [:forge, :storage, :samples_written],
        event_name: [:forge, :storage, :sample_write],
        measurement: :size_bytes,
        tags: [:storage_backend],
        description: "Total number of samples written to storage"
      },
      %{
        type: :counter,
        name: [:forge, :storage, :artifacts_uploaded],
        event_name: [:forge, :storage, :artifact_upload],
        measurement: :size_bytes,
        tags: [:deduplication],
        description: "Total number of artifacts uploaded"
      },
      %{
        type: :counter,
        name: [:forge, :storage, :artifacts_downloaded],
        event_name: [:forge, :storage, :artifact_download],
        measurement: :size_bytes,
        tags: [],
        description: "Total number of artifacts downloaded"
      },

      # Storage Distributions
      %{
        type: :distribution,
        name: [:forge, :storage, :sample_write_duration],
        event_name: [:forge, :storage, :sample_write],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:storage_backend],
        buckets: [10, 50, 100, 500, 1_000, 5_000],
        description: "Sample write operation latency in milliseconds"
      },
      %{
        type: :distribution,
        name: [:forge, :storage, :sample_write_size],
        event_name: [:forge, :storage, :sample_write],
        measurement: :size_bytes,
        unit: :byte,
        tags: [:storage_backend],
        buckets: [1024, 10_240, 102_400, 1_024_000, 10_240_000],
        description: "Sample write size in bytes"
      },
      %{
        type: :distribution,
        name: [:forge, :storage, :artifact_upload_duration],
        event_name: [:forge, :storage, :artifact_upload],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:deduplication],
        buckets: [10, 50, 100, 500, 1_000, 5_000, 30_000],
        description: "Artifact upload latency in milliseconds"
      },
      %{
        type: :distribution,
        name: [:forge, :storage, :artifact_upload_size],
        event_name: [:forge, :storage, :artifact_upload],
        measurement: :size_bytes,
        unit: :byte,
        tags: [:deduplication],
        buckets: [1024, 10_240, 102_400, 1_024_000, 10_240_000, 104_857_600],
        description: "Artifact upload size in bytes"
      },
      %{
        type: :distribution,
        name: [:forge, :storage, :artifact_download_duration],
        event_name: [:forge, :storage, :artifact_download],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [],
        buckets: [10, 50, 100, 500, 1_000, 5_000, 30_000],
        description: "Artifact download latency in milliseconds"
      },

      # DLQ Counters
      %{
        type: :counter,
        name: [:forge, :dlq, :enqueued],
        event_name: [:forge, :dlq, :enqueue],
        measurement: nil,
        tags: [:stage],
        description: "Total number of samples moved to dead-letter queue"
      }
    ]
  end

  @doc """
  Returns counters only.
  """
  def counters do
    Enum.filter(metrics(), fn metric -> metric.type == :counter end)
  end

  @doc """
  Returns distributions only.
  """
  def distributions do
    Enum.filter(metrics(), fn metric -> metric.type == :distribution end)
  end

  @doc """
  Returns metrics for a specific category.

  Categories:
  - `:pipeline` - Pipeline-level metrics
  - `:stage` - Stage execution metrics
  - `:measurement` - Measurement computation metrics
  - `:storage` - Storage operation metrics
  - `:dlq` - Dead-letter queue metrics
  """
  def category(category) when is_atom(category) do
    Enum.filter(metrics(), fn metric ->
      metric.event_name
      |> Enum.at(1)
      |> Kernel.==(category)
    end)
  end
end
