# ADR-003: Stage Composition Model

## Status
Accepted

## Context
Stages are the transformation units in Forge pipelines. Samples flow through a series of stages, each potentially modifying the sample's data, status, or metadata. We need a design that:

1. Provides a simple, composable interface for transformations
2. Supports filtering (removing samples from the pipeline)
3. Allows stages to fail gracefully with error handling
4. Enables both stateless and stateful stages
5. Maintains sample immutability while allowing transformations
6. Supports stage chaining and composition

## Decision

We will implement a `Forge.Stage` behaviour with a minimal, functional interface that emphasizes composition and immutability.

### Core Behaviour

```elixir
defmodule Forge.Stage do
  @callback process(sample :: Forge.Sample.t()) ::
    {:ok, Forge.Sample.t()}
    | {:skip, reason :: any()}
    | {:error, reason :: any()}
end
```

### Design Principles

1. **Single Sample Processing**: Each stage processes one sample at a time
2. **Immutability**: Stages return new sample structs, never mutate
3. **Three Outcomes**:
   - `{:ok, sample}` - Continue with transformed sample
   - `{:skip, reason}` - Remove sample from pipeline
   - `{:error, reason}` - Stage failed, error handling by runner
4. **Stateless by Default**: Stages are modules with a single function
5. **Composable**: Stages can be chained in pipeline configuration

### Stage Types

**Transform Stage**
Modifies sample data while preserving the sample.
```elixir
defmodule Normalize do
  @behaviour Forge.Stage

  def process(sample) do
    normalized = normalize_data(sample.data)
    {:ok, %{sample | data: normalized}}
  end
end
```

**Filter Stage**
Removes samples based on conditions.
```elixir
defmodule FilterInvalid do
  @behaviour Forge.Stage

  def process(sample) do
    if valid?(sample.data) do
      {:ok, sample}
    else
      {:skip, :invalid_data}
    end
  end
end
```

**Enrich Stage**
Adds additional data to samples.
```elixir
defmodule Enrich do
  @behaviour Forge.Stage

  def process(sample) do
    metadata = fetch_metadata(sample.data.id)
    data = Map.put(sample.data, :metadata, metadata)
    {:ok, %{sample | data: data}}
  end
end
```

**Status Stage**
Updates sample lifecycle status.
```elixir
defmodule MarkReady do
  @behaviour Forge.Stage

  def process(sample) do
    {:ok, %{sample | status: :ready}}
  end
end
```

### Runner Integration

The pipeline runner will:
1. Execute stages in the order defined in pipeline config
2. Pass the output of one stage as input to the next
3. Remove samples that return `{:skip, _}`
4. Handle `{:error, _}` according to error policy
5. Collect all successful samples for next pipeline phase

### Composition Patterns

**Conditional Composition**
```elixir
defmodule ConditionalStage do
  def process(sample) do
    if sample.data.needs_processing do
      ComplexStage.process(sample)
    else
      {:ok, sample}
    end
  end
end
```

**Delegating Composition**
```elixir
defmodule MultiStep do
  def process(sample) do
    with {:ok, s1} <- Step1.process(sample),
         {:ok, s2} <- Step2.process(s1),
         {:ok, s3} <- Step3.process(s2) do
      {:ok, s3}
    end
  end
end
```

## Consequences

### Positive
- Simple, easy-to-understand interface
- Functional programming patterns (immutability, composition)
- Clear separation of concerns (one stage, one responsibility)
- Easy to test (pure functions in most cases)
- Flexible error handling
- Natural pipeline composition

### Negative
- Single-sample processing may be less efficient than batch
- Stateful stages require external state management (Agent, ETS, etc.)
- No built-in support for parallel processing within a stage
- Error handling is delegated to the runner

### Neutral
- Stages don't know about other stages in the pipeline
- No standardized way to configure stages (use module attributes or opts)
- Order matters - pipeline defines execution sequence

## Implementation Details

### Error Handling Strategies

**Fail Fast (default)**
```elixir
# Pipeline stops on first error
case Stage.process(sample) do
  {:error, reason} -> raise "Stage failed: #{inspect(reason)}"
  result -> result
end
```

**Skip on Error**
```elixir
# Treat errors as skips
case Stage.process(sample) do
  {:error, reason} -> {:skip, {:error, reason}}
  result -> result
end
```

**Collect Errors**
```elixir
# Continue processing, collect errors
case Stage.process(sample) do
  {:error, reason} ->
    record_error(sample, reason)
    {:skip, :error}
  result -> result
end
```

### Stateful Stages

For stages that need state, use external state management:

```elixir
defmodule StatefulStage do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def process(sample) do
    state = Agent.get(__MODULE__, & &1)
    # Use state...
    Agent.update(__MODULE__, fn s -> new_state end)
    {:ok, sample}
  end
end
```

Or use ETS tables for high-performance state.

## Examples

### Data Transformation
```elixir
defmodule NormalizeValues do
  @behaviour Forge.Stage

  def process(sample) do
    normalized = Enum.map(sample.data.values, &(&1 / 100.0))
    data = Map.put(sample.data, :normalized_values, normalized)
    {:ok, %{sample | data: data}}
  end
end
```

### Validation and Filtering
```elixir
defmodule ValidateSchema do
  @behaviour Forge.Stage

  def process(sample) do
    case validate_schema(sample.data) do
      :ok -> {:ok, sample}
      {:error, errors} -> {:skip, {:validation_failed, errors}}
    end
  end

  defp validate_schema(data) do
    # Validation logic
  end
end
```

### Enrichment
```elixir
defmodule AddTimestamp do
  @behaviour Forge.Stage

  def process(sample) do
    data = Map.put(sample.data, :processed_at, DateTime.utc_now())
    {:ok, %{sample | data: data}}
  end
end
```

### Complex Composition
```elixir
defmodule ProcessingPipeline do
  @behaviour Forge.Stage

  def process(sample) do
    with {:ok, s1} <- Validate.process(sample),
         {:ok, s2} <- Normalize.process(s1),
         {:ok, s3} <- Enrich.process(s2),
         {:ok, s4} <- Transform.process(s3) do
      {:ok, s4}
    end
  end
end
```

## Alternatives Considered

### 1. Batch Processing Interface
```elixir
@callback process(samples :: [Forge.Sample.t()]) :: [Forge.Sample.t()]
```
**Rejected**: More complex, harder to compose, less clear semantics for filtering.

### 2. GenServer-based Stages
Stages as long-running processes.
**Rejected**: Unnecessary overhead for most stages, complicates composition.

### 3. Multi-callback Behaviour
```elixir
@callback init(opts) :: state
@callback process(sample, state) :: {result, state}
@callback cleanup(state) :: :ok
```
**Rejected**: Too complex for simple transformations, stateless stages pay complexity cost.

### 4. Protocol-based Design
```elixir
defprotocol Forge.Stage do
  def process(stage, sample)
end
```
**Rejected**: Behaviours provide better documentation and compile-time checks.

## References
- Functional Programming patterns in Elixir
- Railway-oriented programming: https://fsharpforfunandprofit.com/rop/
- Broadway processors: https://hexdocs.pm/broadway/Broadway.html
