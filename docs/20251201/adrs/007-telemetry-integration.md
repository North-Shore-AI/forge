# ADR-007: Telemetry Integration

## Status
Accepted

## Context

Production ML pipelines require deep observability to diagnose failures, optimize performance, and track costs:

- **Failure diagnosis**: Which stage is failing? What's the error rate? (detect data quality issues, API outages)
- **Performance optimization**: Where are bottlenecks? (slow stages, backpressure, queue buildup)
- **Cost tracking**: How many API calls? Embedding costs? (OpenAI charges $0.0001/1k tokens)
- **SLA monitoring**: Are pipelines meeting latency targets? (detect regressions)
- **Capacity planning**: Queue depth, throughput trends (predict when to scale)

**Current state**:
- v0.1 has no instrumentation
- No visibility into pipeline execution (black box)
- Failures surface as exceptions (no metrics, no context)
- No integration with monitoring stacks (Datadog, Prometheus, CloudWatch)

**Requirements**:

1. **Structured events**: :telemetry-based instrumentation (BEAM standard)
2. **Comprehensive coverage**: Stage start/stop, measurements, retries, DLQ, storage I/O
3. **Rich metadata**: Sample ID, pipeline ID, stage name, error reason (for filtering/grouping)
4. **Performance metrics**: Latency (p50/p95/p99), throughput, error rates
5. **Cost metrics**: API call counts, token usage, storage bytes
6. **Export compatibility**: OpenTelemetry, StatsD, Prometheus (industry standard formats)

### Key Metrics to Track

**Pipeline-level**:
- Runs started/completed/failed (counter)
- Run duration (histogram)
- Samples processed per run (gauge)
- Success rate % (gauge)

**Stage-level**:
- Stage executions (counter, by stage name)
- Stage latency (histogram, by stage)
- Stage failures (counter, by stage + error type)
- Retry attempts (counter, by stage)

**Measurement-level**:
- Measurements computed (counter, by measurement key)
- Measurement latency (histogram, by key)
- Cache hit rate % (gauge, by key)
- Batch size (histogram, for batch measurements)

**Storage-level**:
- Samples written/read (counter)
- Artifacts uploaded/downloaded (counter)
- Storage bytes written (counter)
- Query latency (histogram)

## Decision

### 1. Telemetry Event Schema

Emit structured events using `:telemetry.execute/3`:

```elixir
# Event naming convention: [:forge, :component, :action]
:telemetry.execute(
  [:forge, :pipeline, :start],
  %{system_time: System.system_time()},
  %{pipeline_id: id, run_id: run_id, name: name}
)

:telemetry.execute(
  [:forge, :pipeline, :stop],
  %{duration: duration_ns},
  %{pipeline_id: id, run_id: run_id, outcome: :completed | :failed}
)

:telemetry.execute(
  [:forge, :stage, :start],
  %{system_time: System.system_time()},
  %{sample_id: id, stage: module_name, pipeline_id: pid, run_id: rid}
)

:telemetry.execute(
  [:forge, :stage, :stop],
  %{duration: duration_ns},
  %{sample_id: id, stage: module_name, outcome: :success | :error, error_type: type}
)

:telemetry.execute(
  [:forge, :stage, :retry],
  %{attempt: attempt_num, delay_ms: delay},
  %{sample_id: id, stage: module_name, error: error_reason}
)

:telemetry.execute(
  [:forge, :measurement, :start],
  %{system_time: System.system_time()},
  %{sample_id: id, measurement_key: key, version: v}
)

:telemetry.execute(
  [:forge, :measurement, :stop],
  %{duration: duration_ns},
  %{sample_id: id, measurement_key: key, outcome: :computed | :cached}
)

:telemetry.execute(
  [:forge, :measurement, :batch_complete],
  %{duration: duration_ns, batch_size: count},
  %{measurement_key: key}
)

:telemetry.execute(
  [:forge, :storage, :sample_write],
  %{duration: duration_ns, size_bytes: size},
  %{sample_id: id, storage_backend: backend}
)

:telemetry.execute(
  [:forge, :storage, :artifact_upload],
  %{duration: duration_ns, size_bytes: size},
  %{artifact_key: key, deduplication: true | false}
)

:telemetry.execute(
  [:forge, :dlq, :enqueue],
  %{},
  %{sample_id: id, stage: module_name, error: error_reason}
)
```

### 2. Instrumentation Points

Instrument key execution paths:

#### Pipeline Runner

```elixir
defmodule Forge.Runner.Streaming do
  def run(pipeline, opts) do
    run_id = UUID.uuid4()

    :telemetry.execute(
      [:forge, :pipeline, :start],
      %{system_time: System.system_time()},
      %{pipeline_id: pipeline.id, run_id: run_id, name: pipeline.name}
    )

    start_time = System.monotonic_time()

    result = try do
      execute_pipeline(pipeline, run_id, opts)
    rescue
      e ->
        :telemetry.execute(
          [:forge, :pipeline, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{pipeline_id: pipeline.id, run_id: run_id, exception: e.__struct__}
        )
        reraise e, __STACKTRACE__
    end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:forge, :pipeline, :stop],
      %{duration: duration},
      %{pipeline_id: pipeline.id, run_id: run_id, outcome: :completed}
    )

    result
  end
end
```

#### Stage Executor

```elixir
defmodule Forge.Stage.Executor do
  def apply_stage(sample, stage) do
    metadata = %{
      sample_id: sample.id,
      stage: stage_name(stage),
      pipeline_id: sample.pipeline_id,
      run_id: sample.run_id
    }

    :telemetry.execute(
      [:forge, :stage, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start_time = System.monotonic_time()

    result = stage.process(sample)

    duration = System.monotonic_time() - start_time

    outcome_metadata = case result do
      {:ok, _} ->
        Map.put(metadata, :outcome, :success)

      {:error, error} ->
        metadata
        |> Map.put(:outcome, :error)
        |> Map.put(:error_type, classify_error(error))
    end

    :telemetry.execute(
      [:forge, :stage, :stop],
      %{duration: duration},
      outcome_metadata
    )

    result
  end

  defp classify_error(429), do: :rate_limit
  defp classify_error(error) when is_integer(error) and error >= 500, do: :server_error
  defp classify_error(%Mint.TransportError{}), do: :network_error
  defp classify_error(_), do: :unknown
end
```

#### Measurement Orchestrator

```elixir
defmodule Forge.MeasurementOrchestrator do
  def measure_sample(sample, measurement) do
    key = measurement.key()
    version = measurement.version()

    metadata = %{
      sample_id: sample.id,
      measurement_key: key,
      version: version
    }

    case get_cached_measurement(sample.id, key, version) do
      {:ok, cached} ->
        :telemetry.execute(
          [:forge, :measurement, :stop],
          %{duration: 0},
          Map.put(metadata, :outcome, :cached)
        )
        {:ok, :cached, cached}

      {:error, :not_found} ->
        :telemetry.execute(
          [:forge, :measurement, :start],
          %{system_time: System.system_time()},
          metadata
        )

        start_time = System.monotonic_time()
        {:ok, value} = measurement.compute(sample)
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:forge, :measurement, :stop],
          %{duration: duration},
          Map.put(metadata, :outcome, :computed)
        )

        insert_measurement(sample.id, key, version, value)
        {:ok, :computed, value}
    end
  end
end
```

#### Storage Backend

```elixir
defmodule Forge.Storage.Postgres do
  def insert_sample(sample) do
    metadata = %{
      sample_id: sample.id,
      storage_backend: :postgres
    }

    start_time = System.monotonic_time()
    result = Repo.insert(sample)
    duration = System.monotonic_time() - start_time

    size_bytes = byte_size(:erlang.term_to_binary(sample.data))

    :telemetry.execute(
      [:forge, :storage, :sample_write],
      %{duration: duration, size_bytes: size_bytes},
      metadata
    )

    result
  end
end

defmodule Forge.Storage.Artifact.S3 do
  def put_blob(key, content, opts) do
    start_time = System.monotonic_time()

    {:ok, uri} = upload_to_s3(key, content, opts)

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:forge, :storage, :artifact_upload],
      %{duration: duration, size_bytes: byte_size(content)},
      %{artifact_key: key, deduplication: false}
    )

    {:ok, uri}
  end
end
```

### 3. Metrics Aggregation

Define reporters for common metric types:

```elixir
defmodule Forge.Telemetry do
  def attach_handlers do
    events = [
      [:forge, :pipeline, :start],
      [:forge, :pipeline, :stop],
      [:forge, :stage, :start],
      [:forge, :stage, :stop],
      [:forge, :stage, :retry],
      [:forge, :measurement, :start],
      [:forge, :measurement, :stop],
      [:forge, :storage, :sample_write],
      [:forge, :storage, :artifact_upload],
      [:forge, :dlq, :enqueue]
    ]

    :telemetry.attach_many(
      "forge-metrics",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:forge, :pipeline, :stop], measurements, metadata, _config) do
    # Increment pipeline completion counter
    :telemetry.execute(
      [:forge, :metrics, :pipeline_completed],
      %{count: 1},
      %{outcome: metadata.outcome}
    )

    # Record pipeline duration histogram
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    :telemetry.execute(
      [:forge, :metrics, :pipeline_duration_ms],
      %{value: duration_ms},
      %{pipeline_id: metadata.pipeline_id}
    )
  end

  defp handle_event([:forge, :stage, :stop], measurements, metadata, _config) do
    # Stage execution counter
    :telemetry.execute(
      [:forge, :metrics, :stage_executions],
      %{count: 1},
      %{stage: metadata.stage, outcome: metadata.outcome}
    )

    # Stage latency histogram
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    :telemetry.execute(
      [:forge, :metrics, :stage_latency_ms],
      %{value: duration_ms},
      %{stage: metadata.stage}
    )
  end

  defp handle_event([:forge, :stage, :retry], measurements, metadata, _config) do
    # Retry counter
    :telemetry.execute(
      [:forge, :metrics, :stage_retries],
      %{count: 1},
      %{stage: metadata.stage, attempt: measurements.attempt}
    )
  end

  defp handle_event([:forge, :measurement, :stop], measurements, metadata, _config) do
    outcome = metadata.outcome

    # Cache hit rate tracking
    if outcome == :cached do
      :telemetry.execute(
        [:forge, :metrics, :measurement_cache_hits],
        %{count: 1},
        %{measurement_key: metadata.measurement_key}
      )
    else
      :telemetry.execute(
        [:forge, :metrics, :measurement_cache_misses],
        %{count: 1},
        %{measurement_key: metadata.measurement_key}
      )
    end

    # Measurement latency (only for computed)
    if outcome == :computed do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      :telemetry.execute(
        [:forge, :metrics, :measurement_latency_ms],
        %{value: duration_ms},
        %{measurement_key: metadata.measurement_key}
      )
    end
  end

  defp handle_event([:forge, :dlq, :enqueue], _measurements, metadata, _config) do
    # DLQ counter
    :telemetry.execute(
      [:forge, :metrics, :dlq_enqueued],
      %{count: 1},
      %{stage: metadata.stage, error: metadata.error}
    )
  end

  defp handle_event(_event, _measurements, _metadata, _config), do: :ok
end
```

### 4. StatsD Reporter

Export metrics to StatsD (Datadog, Grafana Cloud):

```elixir
defmodule Forge.Telemetry.StatsDReporter do
  def attach do
    events = [
      [:forge, :metrics, :pipeline_completed],
      [:forge, :metrics, :pipeline_duration_ms],
      [:forge, :metrics, :stage_executions],
      [:forge, :metrics, :stage_latency_ms],
      [:forge, :metrics, :stage_retries],
      [:forge, :metrics, :measurement_latency_ms],
      [:forge, :metrics, :measurement_cache_hits],
      [:forge, :metrics, :dlq_enqueued]
    ]

    :telemetry.attach_many(
      "forge-statsd",
      events,
      &handle_event/4,
      statsd_config()
    )
  end

  defp handle_event([:forge, :metrics, :pipeline_completed], %{count: 1}, metadata, config) do
    Statix.increment("forge.pipeline.completed", 1,
      tags: ["outcome:#{metadata.outcome}"]
    )
  end

  defp handle_event([:forge, :metrics, :pipeline_duration_ms], %{value: duration}, metadata, _) do
    Statix.histogram("forge.pipeline.duration", duration,
      tags: ["pipeline_id:#{metadata.pipeline_id}"]
    )
  end

  defp handle_event([:forge, :metrics, :stage_executions], %{count: 1}, metadata, _) do
    Statix.increment("forge.stage.executions", 1,
      tags: ["stage:#{metadata.stage}", "outcome:#{metadata.outcome}"]
    )
  end

  defp handle_event([:forge, :metrics, :stage_latency_ms], %{value: latency}, metadata, _) do
    Statix.histogram("forge.stage.latency", latency,
      tags: ["stage:#{metadata.stage}"]
    )
  end

  defp handle_event([:forge, :metrics, :stage_retries], %{count: 1}, metadata, _) do
    Statix.increment("forge.stage.retries", 1,
      tags: ["stage:#{metadata.stage}", "attempt:#{metadata.attempt}"]
    )
  end

  defp handle_event([:forge, :metrics, :measurement_latency_ms], %{value: latency}, metadata, _) do
    Statix.histogram("forge.measurement.latency", latency,
      tags: ["measurement:#{metadata.measurement_key}"]
    )
  end

  defp handle_event([:forge, :metrics, :measurement_cache_hits], %{count: 1}, metadata, _) do
    Statix.increment("forge.measurement.cache_hits", 1,
      tags: ["measurement:#{metadata.measurement_key}"]
    )
  end

  defp handle_event([:forge, :metrics, :dlq_enqueued], %{count: 1}, metadata, _) do
    Statix.increment("forge.dlq.enqueued", 1,
      tags: ["stage:#{metadata.stage}", "error:#{metadata.error}"]
    )
  end
end
```

### 5. OpenTelemetry Integration

For distributed tracing (span context propagation):

```elixir
defmodule Forge.Telemetry.OTel do
  require OpenTelemetry.Tracer

  def attach do
    :telemetry.attach_many(
      "forge-otel",
      [
        [:forge, :pipeline, :start],
        [:forge, :pipeline, :stop],
        [:forge, :stage, :start],
        [:forge, :stage, :stop]
      ],
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:forge, :pipeline, :start], _measurements, metadata, _config) do
    OpenTelemetry.Tracer.start_span(
      "forge.pipeline",
      %{
        attributes: %{
          "forge.pipeline.id" => metadata.pipeline_id,
          "forge.run.id" => metadata.run_id,
          "forge.pipeline.name" => metadata.name
        }
      }
    )
  end

  defp handle_event([:forge, :pipeline, :stop], measurements, metadata, _config) do
    OpenTelemetry.Tracer.set_attributes(%{
      "forge.pipeline.outcome" => metadata.outcome,
      "forge.pipeline.duration_ms" => System.convert_time_unit(measurements.duration, :native, :millisecond)
    })

    OpenTelemetry.Tracer.end_span()
  end

  defp handle_event([:forge, :stage, :start], _measurements, metadata, _config) do
    OpenTelemetry.Tracer.start_span(
      "forge.stage",
      %{
        attributes: %{
          "forge.stage.name" => metadata.stage,
          "forge.sample.id" => metadata.sample_id
        }
      }
    )
  end

  defp handle_event([:forge, :stage, :stop], measurements, metadata, _config) do
    OpenTelemetry.Tracer.set_attributes(%{
      "forge.stage.outcome" => metadata.outcome,
      "forge.stage.duration_ms" => System.convert_time_unit(measurements.duration, :native, :millisecond)
    })

    if metadata[:error_type] do
      OpenTelemetry.Tracer.set_attributes(%{"forge.stage.error_type" => metadata.error_type})
    end

    OpenTelemetry.Tracer.end_span()
  end
end
```

### 6. Prometheus Exporter

For pull-based metrics (Kubernetes scraping):

```elixir
defmodule Forge.Telemetry.Prometheus do
  use PromEx.Plugin

  @impl true
  def metrics do
    [
      counter(
        [:forge, :metrics, :pipeline_completed],
        event_name: [:forge, :metrics, :pipeline_completed],
        measurement: :count,
        tags: [:outcome]
      ),

      distribution(
        [:forge, :metrics, :pipeline_duration_ms],
        event_name: [:forge, :metrics, :pipeline_duration_ms],
        measurement: :value,
        unit: {:native, :millisecond},
        tags: [:pipeline_id],
        buckets: [10, 100, 1_000, 10_000, 60_000, 300_000]
      ),

      counter(
        [:forge, :metrics, :stage_executions],
        event_name: [:forge, :metrics, :stage_executions],
        measurement: :count,
        tags: [:stage, :outcome]
      ),

      distribution(
        [:forge, :metrics, :stage_latency_ms],
        event_name: [:forge, :metrics, :stage_latency_ms],
        measurement: :value,
        unit: {:native, :millisecond},
        tags: [:stage],
        buckets: [10, 50, 100, 500, 1_000, 5_000, 30_000]
      ),

      counter(
        [:forge, :metrics, :measurement_cache_hits],
        event_name: [:forge, :metrics, :measurement_cache_hits],
        measurement: :count,
        tags: [:measurement_key]
      ),

      counter(
        [:forge, :metrics, :dlq_enqueued],
        event_name: [:forge, :metrics, :dlq_enqueued],
        measurement: :count,
        tags: [:stage, :error]
      )
    ]
  end
end
```

### 7. Custom Dashboards

Recommended Grafana dashboard queries:

```promql
# Pipeline throughput (samples/sec)
rate(forge_metrics_stage_executions_total[5m])

# Stage error rate
sum(rate(forge_metrics_stage_executions_total{outcome="error"}[5m])) by (stage)
/
sum(rate(forge_metrics_stage_executions_total[5m])) by (stage)

# P95 stage latency
histogram_quantile(0.95, sum(rate(forge_metrics_stage_latency_ms_bucket[5m])) by (le, stage))

# Cache hit rate
sum(rate(forge_metrics_measurement_cache_hits_total[5m])) by (measurement_key)
/
sum(rate(forge_metrics_measurement_cache_hits_total[5m]) + rate(forge_metrics_measurement_cache_misses_total[5m])) by (measurement_key)

# DLQ depth
sum(forge_metrics_dlq_enqueued_total) by (stage)
```

### 8. Logging Integration

Structured logs with trace context:

```elixir
defmodule Forge.Telemetry.Logger do
  require Logger

  def attach do
    :telemetry.attach_many(
      "forge-logger",
      [
        [:forge, :pipeline, :exception],
        [:forge, :stage, :stop],
        [:forge, :dlq, :enqueue]
      ],
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:forge, :pipeline, :exception], _measurements, metadata, _config) do
    Logger.error("Pipeline failed",
      pipeline_id: metadata.pipeline_id,
      run_id: metadata.run_id,
      exception: metadata.exception
    )
  end

  defp handle_event([:forge, :stage, :stop], measurements, metadata, _config) do
    if metadata.outcome == :error do
      Logger.warn("Stage failed",
        sample_id: metadata.sample_id,
        stage: metadata.stage,
        error_type: metadata.error_type,
        duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond)
      )
    end
  end

  defp handle_event([:forge, :dlq, :enqueue], _measurements, metadata, _config) do
    Logger.info("Sample moved to DLQ",
      sample_id: metadata.sample_id,
      stage: metadata.stage,
      error: metadata.error
    )
  end
end
```

## Consequences

### Positive

- **Observability**: Complete visibility into pipeline execution (no black boxes)
- **Debuggability**: Trace failures to specific stages, samples, errors (reduce MTTR)
- **Performance tuning**: Identify bottlenecks via latency histograms (optimize hot paths)
- **Cost tracking**: API call counters enable billing reconciliation (OpenAI, ALTAR)
- **SLA monitoring**: Alert on p95 latency regressions, error rate spikes
- **Capacity planning**: Throughput trends inform scaling decisions

### Negative

- **Overhead**: Telemetry adds ~1-5% latency (acceptable for batch ML)
- **Cardinality explosion**: High-cardinality tags (sample_id) can overwhelm Prometheus (mitigate with sampling)
- **Configuration complexity**: Multiple reporters (StatsD, Prometheus, OpenTelemetry) require separate setup
- **Storage costs**: Prometheus retention at high resolution = $$$; recommend 15d retention, 1m aggregation

### Neutral

- **Sampling**: For high-throughput pipelines (>1k samples/sec), sample telemetry at 1% (configurable)
- **Async emission**: Telemetry execute is synchronous; for critical paths, batch/async dispatch (future work)

### Alternatives Considered

1. **Logs-only** (no metrics):
   - Pro: Simpler (no metric store)
   - Con: Can't aggregate (no histograms), slow queries (grep logs)
   - Rejected: Metrics essential for dashboards, alerting

2. **Custom metrics library** (not :telemetry):
   - Pro: Tailored API
   - Con: Not idiomatic Elixir, poor ecosystem integration
   - Rejected: :telemetry is BEAM standard (Phoenix, Ecto use it)

3. **AppSignal/New Relic** (SaaS APM):
   - Pro: Turnkey, rich UI
   - Con: Vendor lock-in, expensive ($99-$499/month), data egress
   - Rejected: Prefer open standards (Prometheus, OTEL); can layer SaaS on top

4. **No telemetry** (rely on logs):
   - Pro: Zero overhead
   - Con: No observability, can't debug production issues
   - Rejected: Unacceptable for production ML

### Configuration

```elixir
# config/runtime.exs
config :forge, :telemetry,
  reporters: [
    Forge.Telemetry.StatsDReporter,
    Forge.Telemetry.Prometheus,
    Forge.Telemetry.OTel,
    Forge.Telemetry.Logger
  ],
  sampling_rate: 1.0  # 100% (reduce for high-throughput)

config :statix,
  host: System.get_env("STATSD_HOST", "localhost"),
  port: String.to_integer(System.get_env("STATSD_PORT", "8125"))

config :opentelemetry,
  resource: %{
    service_name: "forge",
    service_version: Application.spec(:forge, :vsn)
  }

# Attach handlers on application start
defmodule Forge.Application do
  use Application

  def start(_type, _args) do
    # Attach telemetry handlers
    Forge.Telemetry.attach_handlers()

    reporters = Application.get_env(:forge, :telemetry)[:reporters] || []
    Enum.each(reporters, & &1.attach())

    # ... rest of supervision tree
  end
end
```
