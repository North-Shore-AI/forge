# Telemetry Integration Guide

Forge provides comprehensive telemetry instrumentation following the ADR-007 specification. All pipeline operations emit structured events that can be consumed by various monitoring systems.

## Quick Start

Telemetry events are automatically emitted during pipeline execution. No additional configuration is required for basic event emission.

### Attaching Event Handlers

To observe telemetry events, attach handlers using the `:telemetry` library:

```elixir
:telemetry.attach(
  "my-handler",
  [:forge, :pipeline, :start],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata})
  end,
  nil
)
```

## Event Reference

### Pipeline Events

#### `[:forge, :pipeline, :start]`
Emitted when a pipeline begins execution.

**Measurements:**
- `system_time`: System time when pipeline started (native units)

**Metadata:**
- `pipeline_id`: Pipeline identifier
- `run_id`: Unique run identifier
- `name`: Pipeline name

#### `[:forge, :pipeline, :stop]`
Emitted when a pipeline completes (success or failure).

**Measurements:**
- `duration`: Execution duration (native time units)
- `samples_processed`: Number of samples successfully processed

**Metadata:**
- `pipeline_id`: Pipeline identifier
- `run_id`: Unique run identifier
- `outcome`: `:completed` or `:failed`

#### `[:forge, :pipeline, :exception]`
Emitted when a pipeline crashes with an unhandled exception.

**Measurements:**
- `duration`: Duration before exception (native time units)

**Metadata:**
- `pipeline_id`: Pipeline identifier
- `run_id`: Unique run identifier
- `exception`: Exception module

### Stage Events

#### `[:forge, :stage, :start]`
Emitted when a stage begins processing a sample.

**Measurements:**
- `system_time`: System time when stage started (native units)

**Metadata:**
- `sample_id`: Sample identifier
- `stage`: Stage name
- `pipeline_id`: Pipeline identifier (optional)
- `run_id`: Run identifier (optional)

#### `[:forge, :stage, :stop]`
Emitted when a stage completes processing.

**Measurements:**
- `duration`: Processing duration (native time units)

**Metadata:**
- `sample_id`: Sample identifier
- `stage`: Stage name
- `outcome`: `:success`, `:error`, or `:skip`
- `error_type`: Error classification (optional, only present for errors)

#### `[:forge, :stage, :retry]`
Emitted when a stage is retried after a failure.

**Measurements:**
- `attempt`: Attempt number (1-based)
- `delay_ms`: Delay before next retry in milliseconds

**Metadata:**
- `sample_id`: Sample identifier
- `stage`: Stage name
- `error`: Error reason

### Measurement Events

#### `[:forge, :measurement, :start]`
Emitted when measurement computation begins.

**Measurements:**
- `system_time`: System time when measurement started (native units)

**Metadata:**
- `sample_id`: Sample identifier
- `measurement_key`: Measurement key/name
- `version`: Measurement version

#### `[:forge, :measurement, :stop]`
Emitted when measurement computation completes.

**Measurements:**
- `duration`: Computation duration (native time units)

**Metadata:**
- `sample_id`: Sample identifier
- `measurement_key`: Measurement key/name
- `outcome`: `:computed` or `:cached`

### Storage Events

#### `[:forge, :storage, :sample_write]`
Emitted when a sample is written to storage.

**Measurements:**
- `duration`: Write duration (native time units)
- `size_bytes`: Size of data written in bytes

**Metadata:**
- `sample_id`: Sample identifier
- `storage_backend`: Storage backend (e.g., `:postgres`, `:ets`)

#### `[:forge, :storage, :artifact_upload]`
Emitted when an artifact is uploaded.

**Measurements:**
- `duration`: Upload duration (native time units)
- `size_bytes`: Artifact size in bytes

**Metadata:**
- `artifact_key`: Artifact key/path
- `deduplication`: Whether deduplication was used (boolean)

#### `[:forge, :storage, :artifact_download]`
Emitted when an artifact is downloaded.

**Measurements:**
- `duration`: Download duration (native time units)
- `size_bytes`: Artifact size in bytes

**Metadata:**
- `artifact_key`: Artifact key/path

### DLQ Events

#### `[:forge, :dlq, :enqueue]`
Emitted when a sample is moved to the dead-letter queue.

**Measurements:** (empty map)

**Metadata:**
- `sample_id`: Sample identifier
- `stage`: Stage where failure occurred
- `error`: Error reason

## Metric Definitions

The `Forge.Telemetry.Metrics` module provides pre-defined metric specifications that can be used with various telemetry reporters.

### Available Metrics

```elixir
# Get all metrics
metrics = Forge.Telemetry.Metrics.metrics()

# Get only counters
counters = Forge.Telemetry.Metrics.counters()

# Get only distributions
distributions = Forge.Telemetry.Metrics.distributions()

# Get metrics by category
pipeline_metrics = Forge.Telemetry.Metrics.category(:pipeline)
stage_metrics = Forge.Telemetry.Metrics.category(:stage)
```

### Key Metrics

**Pipeline Metrics:**
- `forge.pipeline.completed` - Total pipeline completions (counter)
- `forge.pipeline.duration` - Pipeline execution time (distribution)

**Stage Metrics:**
- `forge.stage.executions` - Total stage executions (counter)
- `forge.stage.latency` - Stage processing time (distribution)
- `forge.stage.retries` - Retry attempts (counter)

**Storage Metrics:**
- `forge.storage.samples_written` - Samples persisted (counter)
- `forge.storage.sample_write_duration` - Write latency (distribution)
- `forge.storage.artifact_upload_size` - Upload sizes (distribution)

## OpenTelemetry Integration

Forge provides optional OpenTelemetry integration for distributed tracing.

### Setup

1. Add dependencies:

```elixir
def deps do
  [
    {:opentelemetry, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.6"}
  ]
end
```

2. Configure:

```elixir
# config/runtime.exs
config :opentelemetry,
  resource: %{
    service_name: "my_forge_app",
    service_version: "1.0.0"
  }

config :forge, :telemetry,
  reporters: [Forge.Telemetry.OTel]
```

### Spans

OpenTelemetry creates the following spans:

- `forge.pipeline` - Full pipeline execution with attributes:
  - `forge.pipeline.id`
  - `forge.run.id`
  - `forge.pipeline.name`
  - `forge.pipeline.outcome`
  - `forge.pipeline.duration_ms`

- `forge.stage` - Individual stage execution with attributes:
  - `forge.stage.name`
  - `forge.sample.id`
  - `forge.stage.outcome`
  - `forge.stage.duration_ms`
  - `forge.stage.error_type` (if failed)

## Custom Reporters

Create custom reporters to integrate with your monitoring system:

```elixir
defmodule MyApp.TelemetryReporter do
  def attach do
    events = [
      [:forge, :pipeline, :stop],
      [:forge, :stage, :stop]
    ]

    :telemetry.attach_many(
      "my-app-reporter",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:forge, :pipeline, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Send to your monitoring system
    MyMonitoring.report("forge.pipeline.duration", duration_ms, tags: [
      outcome: metadata.outcome,
      pipeline: metadata.pipeline_id
    ])
  end

  defp handle_event([:forge, :stage, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    MyMonitoring.report("forge.stage.duration", duration_ms, tags: [
      stage: metadata.stage,
      outcome: metadata.outcome
    ])
  end
end
```

Then configure it:

```elixir
config :forge, :telemetry,
  reporters: [MyApp.TelemetryReporter]
```

## Examples

### Tracking Stage Performance

```elixir
:telemetry.attach(
  "stage-perf",
  [:forge, :stage, :stop],
  fn _event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if duration_ms > 1000 do
      Logger.warning("Slow stage: #{metadata.stage} took #{duration_ms}ms")
    end
  end,
  nil
)
```

### Monitoring Cache Hit Rate

```elixir
:telemetry.attach(
  "cache-hits",
  [:forge, :measurement, :stop],
  fn _event, _measurements, metadata, _config ->
    if metadata.outcome == :cached do
      # Increment cache hit counter
      :telemetry.execute([:my_app, :measurement, :cache_hit], %{count: 1}, metadata)
    else
      # Increment cache miss counter
      :telemetry.execute([:my_app, :measurement, :cache_miss], %{count: 1}, metadata)
    end
  end,
  nil
)
```

### Alerting on DLQ Depth

```elixir
:telemetry.attach(
  "dlq-alert",
  [:forge, :dlq, :enqueue],
  fn _event, _measurements, metadata, _config ->
    # Increment DLQ counter in your monitoring system
    MyMonitoring.increment("forge.dlq.depth", tags: [stage: metadata.stage])

    # Check if threshold exceeded
    dlq_depth = MyMonitoring.get_gauge("forge.dlq.depth")
    if dlq_depth > 100 do
      MyAlerting.send_alert("DLQ depth exceeded threshold: #{dlq_depth}")
    end
  end,
  nil
)
```

## Best Practices

1. **Use descriptive tags**: Include enough metadata to filter and group metrics effectively
2. **Convert time units**: Always convert native time units to milliseconds for reporting
3. **Sample high-cardinality metrics**: For high-throughput pipelines, consider sampling events with high-cardinality tags (like sample_id)
4. **Aggregate in reporters**: Keep telemetry event handlers lightweight; do heavy aggregation in separate processes
5. **Monitor reporter health**: Track reporter failures to avoid silent monitoring gaps

## Performance Impact

Telemetry adds approximately 1-5% overhead to pipeline execution. For high-throughput scenarios (>1000 samples/sec), consider:

- Reducing the number of attached handlers
- Using async reporters that don't block pipeline execution
- Implementing sampling for high-cardinality events
- Batching metric submissions to reduce network overhead
