# ADR-001: Source Behaviour Design

## Status
Accepted

## Context
Forge needs a flexible mechanism for providing samples to pipelines. Different use cases require different sample sources:
- Static datasets loaded from memory
- Dynamic generation based on functions or algorithms
- External data sources (databases, APIs, file systems)
- Streaming data sources

We need a design that:
1. Provides a consistent interface for all source types
2. Allows custom source implementations
3. Supports both finite and infinite sources
4. Enables efficient resource management
5. Integrates seamlessly with the pipeline execution model

## Decision

We will implement a `Forge.Source` behaviour with the following design:

### Core Behaviour
```elixir
defmodule Forge.Source do
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}
  @callback fetch(state :: any()) :: {:ok, samples :: [map()], new_state :: any()} | {:done, state :: any()}
  @callback cleanup(state :: any()) :: :ok
end
```

### Built-in Implementations

**Forge.Source.Static**
- Provides samples from a pre-defined list
- Returns all samples in a single fetch
- Useful for testing and small datasets
- Configuration: `data: [%{}, ...]`

**Forge.Source.Generator**
- Generates samples using a function
- Supports finite generation with count
- Configuration: `count: integer(), generator: (index -> map())`

### Source Lifecycle
1. **init/1** - Initialize source with configuration, return state
2. **fetch/1** - Retrieve next batch of samples, return updated state
3. **cleanup/1** - Release resources when source is complete

### Integration with Pipeline
The Runner will:
1. Call `init/1` when pipeline starts
2. Repeatedly call `fetch/1` until `{:done, state}` is returned
3. Call `cleanup/1` when pipeline completes or crashes
4. Convert raw data maps to `Forge.Sample` structs

## Consequences

### Positive
- Clear separation between sample generation and pipeline processing
- Easy to implement custom sources for any data provider
- Stateful design allows streaming and pagination
- Batching support enables efficient processing
- Cleanup callback ensures resource safety

### Negative
- Requires implementing three callbacks for simple sources
- State management adds complexity for stateless sources
- No built-in support for concurrent fetching

### Neutral
- Sources are responsible for their own error handling
- Batch size is determined by source implementation
- No standardized metadata format for samples

## Examples

### Static Source Usage
```elixir
source Forge.Source.Static, data: [
  %{value: 1},
  %{value: 2},
  %{value: 3}
]
```

### Generator Source Usage
```elixir
source Forge.Source.Generator,
  count: 1000,
  generator: fn index ->
    %{id: index, value: :rand.uniform()}
  end
```

### Custom Source
```elixir
defmodule MyApp.DatabaseSource do
  @behaviour Forge.Source

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :connection)
    query = Keyword.fetch!(opts, :query)
    {:ok, %{conn: conn, query: query, offset: 0}}
  end

  @impl true
  def fetch(%{offset: offset} = state) do
    case MyApp.DB.fetch_batch(state.conn, state.query, offset, 100) do
      [] -> {:done, state}
      samples -> {:ok, samples, %{state | offset: offset + 100}}
    end
  end

  @impl true
  def cleanup(state) do
    MyApp.DB.close(state.conn)
    :ok
  end
end
```

## Alternatives Considered

### 1. Stream-based API
Instead of callbacks, use Elixir streams:
```elixir
@callback stream(opts) :: Enumerable.t()
```
**Rejected**: Less control over batching and resource management, harder to integrate with GenServer-based runner.

### 2. Single callback with lazy enumeration
```elixir
@callback samples(opts) :: Enumerable.t()
```
**Rejected**: Doesn't provide lifecycle hooks for cleanup, makes error handling harder.

### 3. Protocol-based design
Use protocols instead of behaviours.
**Rejected**: Behaviours provide better compile-time guarantees and documentation.

## References
- Elixir Behaviours: https://hexdocs.pm/elixir/behaviours.html
- GenServer lifecycle patterns
- Broadway source design: https://hexdocs.pm/broadway/
