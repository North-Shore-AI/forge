# ADR-004: Measurement Orchestration

## Status
Accepted

## Context

Forge pipelines generate samples (input data for experiments), but ML training requires **measurements** (features, metrics, embeddings) computed on those samples:

- **Embeddings**: Vector representations (OpenAI/Cohere/Sentence-BERT) for similarity search, clustering
- **Topological features**: Persistence diagrams, Betti numbers (via ALTAR/Snakepit Ripser)
- **Text statistics**: Length, lexical diversity, readability scores
- **Quality scores**: Semantic coherence, factuality (LLM-as-judge)
- **Comparative metrics**: Edit distance, BLEU score (for paired samples)

**Current limitations**:
- v0.1 has `Measurement` behaviour but no orchestration
- No idempotency (re-running measurement duplicates results)
- No async execution (embeddings block sample generation)
- No external compute integration (ALTAR/Snakepit)
- No versioning (changing measurement code invalidates old values)

### Requirements

1. **Decoupled execution**: Measurements run independently of sample generation (don't block pipeline)
2. **Idempotency**: Re-running same measurement on same sample (same version) is no-op
3. **Versioning**: Measurement code changes increment version, old results preserved
4. **External compute**: Support dispatching to ALTAR (Python Celery), Snakepit (LLM workers)
5. **Batch processing**: Vectorize measurements (embed 50 samples in 1 API call)
6. **Observability**: Track measurement latency, failure rates, cache hit rates

### Use Cases

1. **Post-generation enrichment**:
   - Generate 10k samples in pipeline
   - Compute embeddings asynchronously (5min for 10k via batch API)
   - Store embeddings in `forge_measurements` table

2. **Iterative measurement**:
   - Train model on initial features
   - Identify need for new feature (e.g., topological features)
   - Add measurement, run on existing samples (don't regenerate)

3. **Measurement versioning**:
   - Upgrade embedding model (text-embedding-ada-002 → text-embedding-3-small)
   - Increment version, recompute all embeddings
   - Old embeddings preserved for comparison

4. **External compute**:
   - Dispatch 100 samples to Snakepit for Ripser TDA computation
   - Poll for results (async), store in database
   - Handle failures (sample too large, Ripser timeout)

## Decision

### 1. Measurement as Post-Pipeline Stage

Measurements are **not** part of main pipeline; they run separately after samples created:

```elixir
# Generate samples
{:ok, run_id} = Forge.async_run(pipeline)

# Compute measurements (separate operation)
Forge.measure(run_id, [
  Forge.Measurements.Embedding,
  Forge.Measurements.TextStats,
  Forge.Measurements.TopologyFeatures
])
```

**Rationale**:
- Sample generation is stable; measurements evolve (add new features weekly)
- Measurements may fail/timeout independently (don't corrupt samples)
- Different latency profiles (embeddings = 100ms, TDA = 10s per sample)

### 2. Deterministic Measurement IDs

Prevent duplicate measurements via unique constraint:

```sql
CREATE UNIQUE INDEX unique_measurement
ON forge_measurements(sample_id, measurement_key, measurement_version);
```

**Measurement key** = module name + config hash:
```elixir
defmodule Forge.Measurements.Embedding do
  def key do
    config = %{model: "text-embedding-3-small", dimensions: 1536}
    config_hash = :crypto.hash(:sha256, :erlang.term_to_binary(config)) |> Base.encode16()
    "embedding:#{config_hash}"
  end

  def version, do: 1  # increment when code logic changes
end
```

**Idempotency check**:
```elixir
defmodule Forge.MeasurementOrchestrator do
  def measure_sample(sample, measurement_module) do
    key = measurement_module.key()
    version = measurement_module.version()

    case Forge.Storage.Postgres.get_measurement(sample.id, key, version) do
      {:ok, existing} ->
        # Already computed
        {:ok, :cached, existing}

      {:error, :not_found} ->
        # Compute and store
        {:ok, value} = measurement_module.compute(sample)

        Forge.Storage.Postgres.insert_measurement(%{
          id: UUID.uuid4(),
          sample_id: sample.id,
          measurement_key: key,
          measurement_version: version,
          value: value,
          computed_at: DateTime.utc_now()
        })

        {:ok, :computed, value}
    end
  end
end
```

### 3. Async Measurement Execution

Use same streaming architecture as pipelines (ADR-002):

```elixir
defmodule Forge.MeasurementRunner do
  def measure(run_id, measurements, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 10)

    Forge.Storage.Postgres.get_samples_by_run(run_id)
    |> Stream.flat_map(fn sample ->
      # Fan out: 1 sample → N measurements
      Enum.map(measurements, fn m -> {sample, m} end)
    end)
    |> Task.async_stream(
      fn {sample, measurement} ->
        Forge.MeasurementOrchestrator.measure_sample(sample, measurement)
      end,
      max_concurrency: concurrency,
      timeout: 60_000,  # 60s for slow measurements (TDA)
      on_timeout: :kill_task
    )
    |> Stream.run()
  end
end
```

**Fan-out behavior**:
- 1000 samples × 3 measurements = 3000 tasks
- Idempotency prevents re-computation (cache hit after first run)
- Each measurement type can have independent concurrency limits

### 4. Batch-Capable Measurements

Support vectorized measurements for efficiency:

```elixir
defmodule Forge.Measurements.Embedding do
  use Forge.Measurement

  def batch_capable?, do: true
  def batch_size, do: 50  # OpenAI supports 50 texts per request

  # Batch API
  def compute_batch(samples) do
    texts = Enum.map(samples, & &1.data["text"])

    # Single API call for 50 texts
    {:ok, embeddings} = OpenAI.embed(texts, model: "text-embedding-3-small")

    # Return list of {sample_id, value} tuples
    Enum.zip(samples, embeddings)
    |> Enum.map(fn {sample, embedding} ->
      {sample.id, %{vector: embedding, model: "text-embedding-3-small"}}
    end)
  end

  # Fallback for single sample
  def compute(sample) do
    {:ok, [result]} = compute_batch([sample])
    {:ok, result}
  end
end
```

**Batch runner**:
```elixir
defmodule Forge.MeasurementRunner do
  def measure_batched(run_id, measurement, opts) do
    batch_size = measurement.batch_size()

    Forge.Storage.Postgres.get_samples_by_run(run_id)
    # Filter samples missing this measurement
    |> Stream.reject(&has_measurement?(&1, measurement))
    |> Stream.chunk_every(batch_size)
    |> Task.async_stream(
      fn batch ->
        measurement.compute_batch(batch)
        |> Enum.each(fn {sample_id, value} ->
          insert_measurement(sample_id, measurement, value)
        end)
      end,
      max_concurrency: 4  # limit concurrent batch requests
    )
    |> Stream.run()
  end
end
```

**Performance**:
- Non-batched: 10k embeddings × 100ms = 16min
- Batched (50/request): 200 requests × 500ms = 100s (10x faster)

### 5. ALTAR/Snakepit Integration

Dispatch measurements to external Python/LLM workers:

```elixir
defmodule Forge.Measurements.TopologyFeatures do
  use Forge.Measurement

  def compute(sample) do
    # Dispatch to ALTAR Celery worker
    {:ok, task_id} = ALTAR.Client.submit_task("ripser.compute_persistence", %{
      points: sample.data["point_cloud"],
      max_dimension: 2
    })

    # Poll for result (async)
    case ALTAR.Client.await_result(task_id, timeout: 30_000) do
      {:ok, result} ->
        {:ok, %{
          betti_numbers: result["betti_numbers"],
          persistence_diagram: result["diagram"]
        }}

      {:error, :timeout} ->
        {:error, :compute_timeout}
    end
  end

  def timeout, do: 60_000  # 60s for TDA compute
end
```

**Snakepit integration** (LLM workers):
```elixir
defmodule Forge.Measurements.SemanticCoherence do
  use Forge.Measurement

  def compute(sample) do
    prompt = """
    Rate the semantic coherence of this text on a scale of 1-10.
    Text: #{sample.data["text"]}
    """

    {:ok, job_id} = Snakepit.Client.enqueue(prompt, model: "claude-3-5-sonnet")

    case Snakepit.Client.poll_result(job_id, timeout: 20_000) do
      {:ok, response} ->
        score = extract_score(response.body)
        {:ok, %{score: score, reasoning: response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**Failure handling**:
- External compute failures don't crash measurement runner
- Retry policy applies (ADR-003): 3 attempts with exponential backoff
- Timeouts tracked as measurement failures (telemetry + DLQ)

### 6. Measurement Versioning

Increment version when measurement logic changes:

```elixir
defmodule Forge.Measurements.Embedding do
  # Version history:
  # v1: text-embedding-ada-002, 1536 dims
  # v2: text-embedding-3-small, 1536 dims (better quality)
  # v3: text-embedding-3-small, 512 dims (faster retrieval)

  def version, do: 3

  def compute(sample) do
    {:ok, embedding} = OpenAI.embed(
      sample.data["text"],
      model: "text-embedding-3-small",
      dimensions: 512
    )

    {:ok, %{vector: embedding, model: "text-embedding-3-small", dims: 512}}
  end
end
```

**Querying specific versions**:
```elixir
# Get latest version
Forge.Storage.Postgres.get_measurement(sample_id, "embedding:abc123")

# Get specific version
Forge.Storage.Postgres.get_measurement(sample_id, "embedding:abc123", version: 2)

# Compare versions (A/B test embedding quality)
v2_embeddings = get_measurements(run_id, "embedding:abc123", version: 2)
v3_embeddings = get_measurements(run_id, "embedding:abc123", version: 3)
compare_retrieval_quality(v2_embeddings, v3_embeddings)
```

### 7. Measurement Dependencies

Some measurements depend on others (embeddings → clustering):

```elixir
defmodule Forge.Measurements.ClusterLabel do
  use Forge.Measurement

  def dependencies do
    [Forge.Measurements.Embedding]
  end

  def compute(sample) do
    # Fetch dependency measurement
    {:ok, embedding} = Forge.Storage.Postgres.get_measurement(
      sample.id,
      Forge.Measurements.Embedding.key()
    )

    # Compute cluster assignment
    cluster_id = assign_cluster(embedding.value.vector)
    {:ok, %{cluster_id: cluster_id}}
  end
end

# Orchestrator resolves dependencies
defmodule Forge.MeasurementOrchestrator do
  def measure(run_id, measurements) do
    # Topological sort by dependencies
    ordered = topological_sort(measurements)

    Enum.each(ordered, fn m ->
      MeasurementRunner.measure(run_id, m)
    end)
  end
end
```

### 8. Telemetry Events

Emit structured telemetry for observability:

```elixir
# Measurement start
:telemetry.execute(
  [:forge, :measurement, :start],
  %{system_time: System.system_time()},
  %{sample_id: id, measurement: key, version: v}
)

# Measurement complete
:telemetry.execute(
  [:forge, :measurement, :stop],
  %{duration: duration_ns},
  %{sample_id: id, measurement: key, outcome: :computed | :cached}
)

# Batch complete
:telemetry.execute(
  [:forge, :measurement, :batch_complete],
  %{duration: duration_ns, batch_size: count},
  %{measurement: key}
)
```

**Metrics to track**:
- **Cache hit rate**: `cached / (cached + computed)` per measurement
- **Latency p95**: Slow measurements blocking throughput
- **Failure rate**: External compute timeouts
- **Batch efficiency**: Actual batch size vs configured (underutilization)

## Consequences

### Positive

- **Decoupling**: Sample generation doesn't wait for slow measurements (embeddings, TDA)
- **Idempotency**: Safe to re-run measurements (no duplicates, cache hits after first run)
- **Versioning**: Measurement evolution doesn't invalidate old data (A/B test embeddings)
- **Batch efficiency**: 10x speedup for embeddings (50 texts/request vs 1)
- **External compute**: Leverage ALTAR/Snakepit for heavy lifting (Python/TDA/LLM)
- **Incrementality**: Add new measurements to existing samples (don't regenerate)

### Negative

- **Complexity**: Measurement orchestration adds scheduler, dependency resolution, versioning logic
- **Storage overhead**: 3 measurement versions × 10k samples = 30k rows (acceptable, but non-trivial)
- **Cache invalidation**: Changing measurement config changes key → cache miss (by design, but surprising)
- **External compute latency**: ALTAR/Snakepit add network RTT (50-200ms overhead per sample)
- **Dependency conflicts**: Circular dependencies possible (require validation at compile time)

### Neutral

- **Eager vs lazy**: Measurements computed on-demand (not auto-triggered on sample creation); explicit API call required
- **Versioning granularity**: Version per measurement module (not per-config); changing model param = new version
- **Batch size tuning**: Fixed batch size (50) vs dynamic (scale with API quota)

### Alternatives Considered

1. **Measurements as pipeline stages**:
   - Pro: Unified execution model, single API
   - Con: Couples sample generation to measurement latency, can't add measurements retroactively
   - Rejected: Decoupling provides more flexibility

2. **Lazy measurement loading** (compute on first access):
   - Pro: Automatic, no explicit API call
   - Con: Unpredictable latency (user queries sample, waits 5s for embedding), hard to batch
   - Rejected: Explicit orchestration more controllable

3. **Materialized view** (Postgres REFRESH MATERIALIZED VIEW):
   - Pro: Declarative, database-native
   - Con: All-or-nothing refresh (can't incrementally add measurements), no external compute
   - Rejected: Too rigid for ML workflows

4. **Event-driven** (sample created → trigger measurement jobs):
   - Pro: Automatic enrichment
   - Con: Measurement selection not explicit (hard to control which run), versioning unclear
   - Rejected: Explicit API more predictable

5. **No versioning** (overwrite on change):
   - Pro: Simpler schema (no version column)
   - Con: Can't compare embedding quality, breaks reproducibility
   - Rejected: Versioning critical for ML experiments

### Integration with Anvil

Export samples with measurements for labeling:

```elixir
defmodule ForgeBridge do
  def export_to_anvil(run_id, queue_name) do
    samples = Forge.Storage.Postgres.get_samples_by_run(run_id)

    Enum.each(samples, fn sample ->
      # Fetch all measurements
      measurements = Forge.Storage.Postgres.get_measurements(sample.id)

      # Convert to Anvil DTO
      anvil_sample = %{
        sample_id: sample.id,
        title: sample.data["title"],
        body: sample.data["text"],
        metadata: %{
          pipeline_id: sample.pipeline_id,
          measurements: measurements
        }
      }

      Anvil.Queue.enqueue(queue_name, anvil_sample)
    end)
  end
end
```

Anvil UI can display measurements alongside labels (e.g., "Embedding distance: 0.87" while labeling contradictions).

### Future Enhancements

1. **Streaming measurements**: Update measurements as samples flow (not batch post-process)
2. **Measurement pipelines**: Chain measurements (embedding → PCA → cluster)
3. **Delta measurements**: Only recompute changed samples (CDC triggers)
4. **GPU batch processing**: Dispatch 1000 samples to GPU worker for BERT encoding
