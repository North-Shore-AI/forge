# ADR-004: Measurement Computation Strategy

## Status
Accepted

## Context
Measurements are computations performed on samples to extract metrics, statistics, or derived values. Different use cases have different requirements:

1. **Simple metrics** (count, sum) are fast and synchronous
2. **Complex computations** (statistical analysis, ML inference) may be expensive
3. **Aggregate measurements** operate on multiple samples
4. **Per-sample measurements** operate on individual samples
5. Some measurements may benefit from parallel/async execution
6. Results need to be attached to samples or stored separately

We need a design that:
- Supports both fast and slow computations
- Allows async execution for expensive operations
- Works with both individual and aggregate measurements
- Integrates cleanly with the pipeline execution model
- Provides clear error handling

## Decision

We will implement a `Forge.Measurement` behaviour with support for both synchronous and asynchronous computation modes.

### Core Behaviour

```elixir
defmodule Forge.Measurement do
  @callback compute(samples :: [Forge.Sample.t()]) ::
    {:ok, results :: map()} | {:error, reason :: any()}

  @callback async?() :: boolean()

  @optional_callbacks [async?: 0]
end
```

### Design Principles

1. **Batch-oriented**: Measurements operate on lists of samples
2. **Flexible Results**: Return a map of measurement results
3. **Async Flag**: Declare if measurement should run asynchronously
4. **Simple Interface**: Single compute function for all measurements
5. **Pipeline Integration**: Measurements run after all stages complete

### Execution Modes

**Synchronous Measurements** (default)
- `async?/0` returns `false` or not implemented
- Computed inline during pipeline execution
- Block pipeline completion
- Results immediately available

```elixir
defmodule SimpleMean do
  @behaviour Forge.Measurement

  def compute(samples) do
    values = Enum.map(samples, & &1.data.value)
    mean = Enum.sum(values) / length(values)
    {:ok, %{mean: mean}}
  end

  def async?(), do: false
end
```

**Asynchronous Measurements**
- `async?/0` returns `true`
- Executed in separate task
- Don't block pipeline completion
- Results stored separately or merged later

```elixir
defmodule ExpensiveAnalysis do
  @behaviour Forge.Measurement

  def compute(samples) do
    # Expensive computation
    result = perform_complex_analysis(samples)
    {:ok, %{analysis: result}}
  end

  def async?(), do: true
end
```

### Runner Integration

The pipeline runner will:

1. **Collect Measurements**: Group by sync/async flag
2. **Execute Sync First**: Run all synchronous measurements
3. **Merge Sync Results**: Add results to sample metadata
4. **Spawn Async Tasks**: Start async measurements in separate tasks
5. **Return Samples**: Don't wait for async measurements
6. **Store Async Results**: When complete, store in configured backend

### Result Handling

**Synchronous Results**
Merged into sample measurements map:
```elixir
%Forge.Sample{
  measurements: %{
    mean: 42.5,
    std_dev: 10.2,
    count: 100
  },
  measured_at: ~U[2025-01-01 12:00:00Z]
}
```

**Asynchronous Results**
Stored in storage backend with reference:
```elixir
# Stored separately
%{
  pipeline: :my_pipeline,
  run_id: "abc123",
  measurement: ExpensiveAnalysis,
  result: %{...},
  computed_at: ~U[2025-01-01 12:05:00Z]
}
```

### Measurement Types

**Aggregate Measurements**
Single result across all samples:
```elixir
defmodule Statistics do
  def compute(samples) do
    values = Enum.map(samples, & &1.data.value)
    {:ok, %{
      mean: Statistics.mean(values),
      median: Statistics.median(values),
      std_dev: Statistics.std_dev(values)
    }}
  end
end
```

**Per-Sample Measurements**
Individual results for each sample:
```elixir
defmodule ScoreEach do
  def compute(samples) do
    scores = Enum.map(samples, fn sample ->
      {sample.id, calculate_score(sample)}
    end)
    {:ok, Map.new(scores)}
  end
end
```

## Consequences

### Positive
- Clear separation between sync and async computations
- Simple interface for implementing measurements
- Flexibility in result formats
- Pipeline doesn't block on expensive measurements
- Easy to test (just functions)
- Can scale async measurements independently

### Negative
- Async results not immediately available
- Requires coordination for async result retrieval
- No built-in progress tracking for async measurements
- Error handling for async tasks needs special consideration
- Per-sample async measurements may have high overhead

### Neutral
- Measurements are always batch-oriented
- Results format is flexible but not standardized
- No built-in caching or memoization
- Measurements don't affect sample flow through pipeline

## Implementation Details

### Synchronous Execution

```elixir
defp run_sync_measurements(samples, measurements) do
  results = Enum.reduce(measurements, %{}, fn {module, _opts}, acc ->
    case module.compute(samples) do
      {:ok, result} -> Map.merge(acc, result)
      {:error, reason} -> raise "Measurement failed: #{inspect(reason)}"
    end
  end)

  Enum.map(samples, fn sample ->
    %{sample |
      measurements: Map.merge(sample.measurements, results),
      measured_at: DateTime.utc_now(),
      status: :measured
    }
  end)
end
```

### Asynchronous Execution

```elixir
defp run_async_measurements(samples, measurements, run_id) do
  Enum.each(measurements, fn {module, _opts} ->
    Task.start(fn ->
      case module.compute(samples) do
        {:ok, result} ->
          store_async_result(run_id, module, result)
        {:error, reason} ->
          Logger.error("Async measurement failed: #{inspect(reason)}")
      end
    end)
  end)
end
```

### Error Handling

**Synchronous Errors**
- Fail fast by default
- Option to continue and log errors
- Include partial results

**Asynchronous Errors**
- Log and continue
- Store error information
- Optional callbacks for error notification

## Examples

### Simple Statistics
```elixir
defmodule BasicStats do
  @behaviour Forge.Measurement

  def compute(samples) do
    values = Enum.map(samples, & &1.data.value)

    {:ok, %{
      count: length(values),
      sum: Enum.sum(values),
      min: Enum.min(values),
      max: Enum.max(values)
    }}
  end
end
```

### Distribution Analysis
```elixir
defmodule Distribution do
  @behaviour Forge.Measurement

  def compute(samples) do
    values = Enum.map(samples, & &1.data.value)
    histogram = create_histogram(values, bins: 10)

    {:ok, %{
      histogram: histogram,
      percentiles: calculate_percentiles(values)
    }}
  end

  def async?(), do: false
end
```

### Machine Learning Inference
```elixir
defmodule MLInference do
  @behaviour Forge.Measurement

  def compute(samples) do
    # Load model and run inference
    model = load_model()
    predictions = Enum.map(samples, fn sample ->
      {sample.id, predict(model, sample.data)}
    end)

    {:ok, %{predictions: Map.new(predictions)}}
  end

  def async?(), do: true  # Expensive, run async
end
```

### Quality Metrics
```elixir
defmodule QualityMetrics do
  @behaviour Forge.Measurement

  def compute(samples) do
    metrics = %{
      valid_count: count_valid(samples),
      invalid_count: count_invalid(samples),
      completion_rate: calculate_completion(samples),
      quality_score: calculate_quality(samples)
    }

    {:ok, metrics}
  end
end
```

## Alternatives Considered

### 1. Per-Sample Measurements Only
```elixir
@callback compute(sample :: Forge.Sample.t()) :: {:ok, map()}
```
**Rejected**: Can't compute aggregate statistics efficiently, forces duplicate work.

### 2. Separate Behaviours for Sync/Async
```elixir
defmodule Forge.Measurement.Sync
defmodule Forge.Measurement.Async
```
**Rejected**: Unnecessary complexity, harder to switch between modes.

### 3. Stream-based Processing
```elixir
@callback compute(samples :: Enumerable.t()) :: Enumerable.t()
```
**Rejected**: Harder to reason about, doesn't fit batch processing model.

### 4. Always Async with Timeouts
All measurements async, with configurable timeouts.
**Rejected**: Overhead for simple measurements, complicates simple use cases.

### 5. Declarative Measurement DSL
```elixir
measurement :mean, field: :value, function: :avg
```
**Rejected**: Less flexible, can't handle complex computations.

## References
- Task and async patterns: https://hexdocs.pm/elixir/Task.html
- Broadway batching: https://hexdocs.pm/broadway/Broadway.html
- GenStage producers/consumers: https://hexdocs.pm/gen_stage/
