# ADR-002: Execution Engine Design

## Status
Accepted

## Context

Forge v0.1 implements a naive runner that eagerly evaluates all samples in a single pass with no concurrency control, backpressure, or async stage execution. This is acceptable for toy datasets (<100 samples) but breaks down for production workloads:

- **Memory exhaustion**: Loading 100k samples into memory OOMs BEAM (each sample ~10KB = 1GB total)
- **No backpressure**: Downstream systems (ALTAR, Snakepit, embedding APIs) throttle but runner doesn't adapt
- **Blocking stages**: LLM calls (5-30s latency) serialize entire pipeline
- **No observability**: Can't pause/resume/inspect in-flight runs
- **Single-node only**: No distributed execution for multi-machine scale

The execution engine must support:

1. **Streaming execution**: Process samples lazily (pull model) to bound memory
2. **Backpressure**: Demand-based flow control to avoid overwhelming downstream
3. **Async stages**: Concurrent execution for I/O-bound stages (LLM, embedding, HTTP APIs)
4. **Batch modes**: Configurable batching for vectorized operations (embedding 50 samples at once)
5. **Resumability**: Persist run state for crash recovery
6. **Distributed execution** (optional): Multi-node processing for large-scale pipelines

### Current API

```elixir
# v0.1: returns list (eagerly evaluated)
samples = Forge.run(pipeline)
```

### Proposed API

```elixir
# v0.2: returns stream handle
run = Forge.run(pipeline,
  concurrency: 10,
  batch_size: 50,
  storage: Forge.Storage.Postgres,
  runner: Forge.Runner.Streaming
)

# Consumer controls flow
run
|> Stream.take(1000)
|> Enum.to_list()

# Or async with progress tracking
{:ok, run_id} = Forge.async_run(pipeline, storage: Postgres)
Forge.await_run(run_id, timeout: :infinity)
```

### Design Constraints

- Must remain Elixir-native (no GenStage dependency if avoidable; BEAM primitives preferred)
- Async stages must respect concurrency limits (not spawn unbounded processes)
- Backpressure must propagate to source (stop pulling samples if downstream slow)
- Errors in one sample must not crash entire run (item-level fault tolerance)
- Must support both streaming (long-running experiments) and batch (quick jobs) modes

## Decision

Implement a **hybrid runner architecture** with two modes:

### 1. Streaming Runner (default)

Built on `Stream` + `Task.async_stream/3` for backpressure and concurrency:

```elixir
defmodule Forge.Runner.Streaming do
  def run(pipeline, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    storage = Keyword.get(opts, :storage, Forge.Storage.ETS)

    pipeline.source
    |> generate_stream()
    |> apply_stages(pipeline.stages, concurrency)
    |> persist_samples(storage)
  end

  defp apply_stages(stream, stages, concurrency) do
    Enum.reduce(stages, stream, fn stage, acc ->
      if async_stage?(stage) do
        # Async I/O-bound stages (LLM, embeddings)
        Task.async_stream(
          acc,
          fn sample -> apply_stage(sample, stage) end,
          max_concurrency: concurrency,
          ordered: false,  # allow reordering for throughput
          timeout: stage_timeout(stage),
          on_timeout: :kill_task
        )
        |> Stream.map(fn {:ok, result} -> result end)
      else
        # Sync CPU-bound stages (filters, transforms)
        Stream.map(acc, fn sample -> apply_stage(sample, stage) end)
      end
    end)
  end

  defp async_stage?(stage) do
    # Check if stage implements async?/0 callback
    function_exported?(stage.__struct__, :async?, 0) and stage.async?()
  end
end
```

**Backpressure mechanism**:
- `Task.async_stream` uses bounded mailbox (max_concurrency tasks in flight)
- When all workers busy, stream stops pulling from source
- Source generator blocks until demand signal
- Propagates to external APIs (ALTAR HTTP requests pause)

**Memory bounds**:
- Stream processing: only `max_concurrency` samples in memory
- Example: 10 concurrent tasks × 10KB/sample = 100KB resident (vs 1GB for eager list)

### 2. Batch Runner (optional)

For vectorized operations (embedding models, matrix operations):

```elixir
defmodule Forge.Runner.Batch do
  def run(pipeline, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 50)

    pipeline.source
    |> generate_stream()
    |> Stream.chunk_every(batch_size)
    |> Task.async_stream(
      fn batch -> apply_stages_batched(batch, pipeline.stages) end,
      max_concurrency: opts[:concurrency] || 4
    )
    |> Stream.flat_map(fn {:ok, results} -> results end)
  end

  defp apply_stages_batched(samples, stages) do
    Enum.reduce(stages, samples, fn stage, batch ->
      if batch_capable?(stage) do
        # Stage implements process_batch/1
        stage.process_batch(batch)
      else
        # Fallback: map individual samples
        Enum.map(batch, &stage.process/1)
      end
    end)
  end
end
```

**When to use batch mode**:
- Embedding stages calling OpenAI/Cohere batch APIs (50 texts → 1 request)
- Matrix operations on Nx tensors (vectorized compute)
- Database bulk inserts (100 samples → 1 COPY command)

### 3. Persisted Runs (resumability)

Add `Forge.Run` schema for tracking execution state:

```elixir
create table(:forge_runs) do
  add :id, :uuid, primary_key: true
  add :pipeline_id, references(:forge_pipelines, type: :uuid), null: false
  add :status, :string, null: false  # running/paused/completed/failed
  add :samples_processed, :integer, default: 0
  add :samples_failed, :integer, default: 0
  add :checkpoint, :map  # cursor state for resumption
  add :started_at, :utc_datetime_usec
  add :completed_at, :utc_datetime_usec
end

# API
{:ok, run_id} = Forge.async_run(pipeline, storage: Postgres)
Forge.pause_run(run_id)
Forge.resume_run(run_id)  # picks up from checkpoint
```

**Checkpoint strategy**:
- After every N samples (configurable), store cursor in `checkpoint` JSONB
- On resume, skip already-processed samples (query by run_id + status)
- Source must support resumable iteration (cursor-based, not offset-based for large datasets)

### 4. Distributed Execution (via Oban or Broadway)

**Optional** for multi-node scale. Not MVP but architecture supports:

#### Option A: Oban Worker

```elixir
defmodule Forge.Workers.PipelineRunner do
  use Oban.Worker, queue: :forge, max_attempts: 3

  @impl Oban.Worker
  def perform(%Job{args: %{"pipeline_id" => id, "sample_ids" => ids}}) do
    pipeline = Forge.Pipeline.get!(id)
    samples = Forge.Storage.Postgres.get_samples(ids)

    Enum.each(samples, fn sample ->
      apply_stages(sample, pipeline.stages)
      |> Forge.Storage.Postgres.update_sample()
    end)
  end
end

# Enqueue samples in batches
sample_ids |> Enum.chunk_every(100) |> Enum.each(fn chunk ->
  %{pipeline_id: p.id, sample_ids: chunk}
  |> Forge.Workers.PipelineRunner.new()
  |> Oban.insert()
end)
```

**Pros**: Battle-tested, retries, DLQ, dashboard
**Cons**: Requires Oban setup, adds latency (queue + polling)

#### Option B: Broadway Pipeline

```elixir
defmodule Forge.Broadway.SampleProcessor do
  use Broadway

  def start_link(pipeline) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Forge.Producer, pipeline: pipeline},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 10]
      ],
      batchers: [
        storage: [concurrency: 5, batch_size: 100]
      ]
    )
  end

  @impl Broadway
  def handle_message(_, %Broadway.Message{data: sample} = message, _) do
    # Apply stages
    message
  end

  @impl Broadway
  def handle_batch(:storage, messages, _, _) do
    samples = Enum.map(messages, & &1.data)
    Forge.Storage.Postgres.insert_samples(samples)
    messages
  end
end
```

**Pros**: Native backpressure, batching, telemetry
**Cons**: More complex than `Task.async_stream`, overkill for <100k samples

### Chosen Defaults

- **MVP (v0.2)**: Streaming runner with `Task.async_stream`
- **Opt-in**: Batch runner for vectorized stages (via `runner: Forge.Runner.Batch`)
- **Future**: Oban/Broadway for distributed execution (v0.3+)

### Concurrency Configuration

Per-stage concurrency overrides:

```elixir
defmodule MyLLMStage do
  use Forge.Stage

  def async?, do: true
  def concurrency, do: 5  # limit to 5 concurrent LLM calls
end

# Runner respects stage-level config
apply_stages(stream, stages, _default_concurrency = 10)
# → LLM stage uses 5, others use 10
```

### Timeout Handling

```elixir
defmodule Forge.Runner.Streaming do
  defp stage_timeout(stage) do
    if function_exported?(stage.__struct__, :timeout, 0) do
      stage.timeout()
    else
      30_000  # default 30s
    end
  end
end
```

Stages exceeding timeout are killed; sample marked as failed (not retried inline; see ADR-003 for retry policy).

## Consequences

### Positive

- **Memory efficiency**: Streaming + backpressure bounds memory to O(concurrency), not O(dataset_size)
- **Throughput**: Async stages achieve 10-50x speedup for I/O-bound workloads (measured: 1k LLM samples in 5min vs 50min sync)
- **Observability**: Persisted runs enable pause/resume, progress tracking, failure analysis
- **Flexibility**: Batch mode supports vectorized stages; streaming mode suitable for 99% of cases
- **Standard patterns**: `Task.async_stream` is well-understood BEAM primitive (vs custom GenStage)
- **Incremental complexity**: Start simple (streaming), opt-in to batch/distributed as needed

### Negative

- **Stream API complexity**: Consumers must understand lazy evaluation, backpressure (vs simple `Enum.map`)
- **Debugging harder**: Async errors surface as `{:exit, reason}` tuples, not stack traces
- **No cross-sample state**: Each sample processed independently (can't aggregate metrics mid-stream; must persist and query)
- **Oban/Broadway overhead**: Distributed execution adds queue latency (100-500ms), not suitable for real-time
- **Testing complexity**: Must mock async I/O, handle race conditions in test suite

### Neutral

- **Ordered vs unordered**: Default `ordered: false` for throughput; stages needing order can override (at cost)
- **Timeout tuning**: Aggressive timeouts (30s) prevent zombie processes but may kill slow LLM calls (configurable per stage)
- **Checkpoint granularity**: Every 1000 samples = ~10s overhead; too frequent = DB write amplification

### Alternatives Considered

1. **GenStage/Flow**:
   - Pro: Native backpressure primitives, multi-stage pipelines
   - Con: Complex API, deprecated in favor of Broadway, overkill for linear pipelines
   - Rejected: `Task.async_stream` achieves 90% of benefits with 10% of complexity

2. **Poolboy + GenServer workers**:
   - Pro: Fine-grained control, custom supervision
   - Con: Reinventing backpressure, no streaming, verbose boilerplate
   - Rejected: Not idiomatic; `Task` + `Stream` are BEAM best practices

3. **Eager evaluation with DB paging**:
   - Pro: Simple to implement (OFFSET/LIMIT queries)
   - Con: Slow for large offsets (query time = O(offset)), brittle for concurrent writes
   - Rejected: Streaming avoids offset pagination antipattern

4. **Broadway from day 1**:
   - Pro: Production-ready, telemetry, batching built-in
   - Con: Steep learning curve, complex config, heavy dependency
   - Rejected: Over-engineering for MVP; can adopt later without breaking API

### Migration Path

v0.1 → v0.2 breaking change:
```elixir
# Old (v0.1)
samples = Forge.run(pipeline)

# New (v0.2)
samples = Forge.run(pipeline) |> Enum.to_list()
# Or streaming
Forge.run(pipeline) |> Stream.each(&process/1) |> Stream.run()
```

Mitigation: Provide `Forge.run!/1` helper that eagerly evaluates for backward compat (deprecated).
