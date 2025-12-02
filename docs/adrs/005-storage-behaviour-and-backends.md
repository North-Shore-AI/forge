# ADR-005: Storage Behaviour and Backends

## Status
Accepted

## Context
Forge needs a mechanism to persist samples after pipeline processing. Different applications have different storage requirements:

1. **In-memory** for testing and small datasets
2. **Disk-based** for large datasets and persistence
3. **Database** for queryable storage and integration
4. **Cloud storage** for distributed systems
5. **Streaming** to external systems (Kafka, etc.)

We need a design that:
- Provides a pluggable storage abstraction
- Supports both synchronous and asynchronous writes
- Handles batch and individual sample storage
- Enables querying and retrieval
- Provides error handling and retry logic
- Integrates seamlessly with pipeline execution

## Decision

We will implement a `Forge.Storage` behaviour with a minimal, flexible interface that supports various storage backends.

### Core Behaviour

```elixir
defmodule Forge.Storage do
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @callback store(samples :: [Forge.Sample.t()], state :: any()) ::
    {:ok, state :: any()} | {:error, reason :: any()}

  @callback retrieve(id :: String.t(), state :: any()) ::
    {:ok, Forge.Sample.t(), state :: any()} | {:error, reason :: any()}

  @callback list(filters :: keyword(), state :: any()) ::
    {:ok, [Forge.Sample.t()], state :: any()} | {:error, reason :: any()}

  @callback cleanup(state :: any()) :: :ok

  @optional_callbacks [retrieve: 2, list: 2]
end
```

### Design Principles

1. **Stateful Interface**: Storage backends maintain connection state
2. **Batch-First**: Primary operation is storing multiple samples
3. **Optional Retrieval**: Not all backends need query support
4. **Lifecycle Management**: Init and cleanup for resource handling
5. **Flexible State**: Backends manage their own state format

### Built-in Implementations

**Forge.Storage.ETS**
- In-memory storage using ETS tables
- Fast read/write operations
- Queryable with filters
- Data lost on process termination
- Configuration: `table: atom(), type: :set | :ordered_set`

```elixir
defmodule Forge.Storage.ETS do
  @behaviour Forge.Storage

  def init(opts) do
    table = Keyword.get(opts, :table, :forge_samples)
    type = Keyword.get(opts, :type, :set)
    ^table = :ets.new(table, [:named_table, type, :public])
    {:ok, %{table: table}}
  end

  def store(samples, %{table: table} = state) do
    Enum.each(samples, fn sample ->
      :ets.insert(table, {sample.id, sample})
    end)
    {:ok, state}
  end

  def retrieve(id, %{table: table} = state) do
    case :ets.lookup(table, id) do
      [{^id, sample}] -> {:ok, sample, state}
      [] -> {:error, :not_found}
    end
  end

  def list(filters, %{table: table} = state) do
    samples = :ets.tab2list(table)
    |> Enum.map(fn {_id, sample} -> sample end)
    |> apply_filters(filters)

    {:ok, samples, state}
  end

  def cleanup(%{table: table}) do
    :ets.delete(table)
    :ok
  end
end
```

**Future Implementations** (not in initial release):
- `Forge.Storage.Disk` - File-based storage (JSON, Parquet)
- `Forge.Storage.Postgres` - PostgreSQL backend
- `Forge.Storage.S3` - AWS S3 storage
- `Forge.Storage.Stream` - Stream to external systems

### Runner Integration

The pipeline runner will:

1. **Initialize**: Call `init/1` at startup
2. **Store Samples**: Call `store/2` after processing
3. **Handle Errors**: Retry or fail based on configuration
4. **Cleanup**: Call `cleanup/1` on shutdown

### Storage Patterns

**Write-Only Pattern**
For pipelines that don't need retrieval:
```elixir
pipeline :write_only do
  source MySource
  stage MyStage
  storage Forge.Storage.Stream, topic: "output"
end
```

**Queryable Pattern**
For pipelines that need sample lookup:
```elixir
# Store samples
Forge.Runner.run(runner)

# Later, retrieve
{:ok, sample, _state} = Forge.Storage.ETS.retrieve(id, state)
```

**Filtered Retrieval**
```elixir
{:ok, samples, _state} = Forge.Storage.ETS.list(
  [pipeline: :my_pipeline, status: :ready],
  state
)
```

## Consequences

### Positive
- Pluggable storage backends for different use cases
- Simple interface with optional advanced features
- Stateful design supports connection pooling
- Batch operations for efficiency
- Clear lifecycle management
- Easy to test with in-memory backend

### Negative
- State management adds complexity
- No built-in transactions or consistency guarantees
- No standardized query language (filters are backend-specific)
- Async storage requires additional coordination

### Neutral
- Backends responsible for their own error handling
- No built-in indexing (backend-specific)
- No standardized serialization format
- Retrieval is optional (not all use cases need it)

## Implementation Details

### Error Handling

**Retry Logic**
```elixir
defp store_with_retry(samples, state, attempts \\ 3) do
  case Storage.store(samples, state) do
    {:ok, new_state} ->
      {:ok, new_state}
    {:error, reason} when attempts > 1 ->
      Logger.warn("Storage failed, retrying: #{inspect(reason)}")
      :timer.sleep(100)
      store_with_retry(samples, state, attempts - 1)
    {:error, reason} ->
      {:error, reason}
  end
end
```

**Partial Success**
```elixir
# Store samples individually on batch failure
defp store_individually(samples, state) do
  {successes, failures} = Enum.reduce(samples, {[], []}, fn sample, {ok, err} ->
    case Storage.store([sample], state) do
      {:ok, _} -> {[sample | ok], err}
      {:error, reason} -> {ok, [{sample, reason} | err]}
    end
  end)

  if Enum.empty?(failures) do
    {:ok, state}
  else
    {:partial, Enum.reverse(successes), Enum.reverse(failures)}
  end
end
```

### Filtering Implementation

```elixir
defp apply_filters(samples, filters) do
  Enum.reduce(filters, samples, fn
    {:pipeline, name}, acc ->
      Enum.filter(acc, &(&1.pipeline == name))

    {:status, status}, acc ->
      Enum.filter(acc, &(&1.status == status))

    {:after, datetime}, acc ->
      Enum.filter(acc, &(DateTime.compare(&1.created_at, datetime) == :gt))

    {:before, datetime}, acc ->
      Enum.filter(acc, &(DateTime.compare(&1.created_at, datetime) == :lt))

    _other, acc ->
      acc
  end)
end
```

## Examples

### ETS Storage
```elixir
# In pipeline config
storage Forge.Storage.ETS, table: :my_samples

# Manual usage
{:ok, state} = Forge.Storage.ETS.init(table: :test)
{:ok, state} = Forge.Storage.ETS.store(samples, state)
{:ok, retrieved, state} = Forge.Storage.ETS.retrieve("id-123", state)
{:ok, all_samples, state} = Forge.Storage.ETS.list([], state)
:ok = Forge.Storage.ETS.cleanup(state)
```

### Custom Disk Storage
```elixir
defmodule MyApp.DiskStorage do
  @behaviour Forge.Storage

  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    File.mkdir_p!(path)
    {:ok, %{path: path}}
  end

  def store(samples, %{path: path} = state) do
    Enum.each(samples, fn sample ->
      filename = Path.join(path, "#{sample.id}.json")
      json = Jason.encode!(sample)
      File.write!(filename, json)
    end)
    {:ok, state}
  end

  def retrieve(id, %{path: path} = state) do
    filename = Path.join(path, "#{id}.json")
    case File.read(filename) do
      {:ok, json} ->
        sample = Jason.decode!(json, keys: :atoms)
        {:ok, sample, state}
      {:error, _} ->
        {:error, :not_found}
    end
  end

  def cleanup(_state), do: :ok
end
```

### Database Storage
```elixir
defmodule MyApp.PostgresStorage do
  @behaviour Forge.Storage

  def init(opts) do
    {:ok, conn} = Postgrex.start_link(opts)
    create_table(conn)
    {:ok, %{conn: conn}}
  end

  def store(samples, %{conn: conn} = state) do
    Enum.each(samples, fn sample ->
      Postgrex.query!(conn, """
        INSERT INTO samples (id, pipeline, data, measurements, status, created_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (id) DO UPDATE
        SET data = $3, measurements = $4, status = $5
      """, [
        sample.id,
        to_string(sample.pipeline),
        Jason.encode!(sample.data),
        Jason.encode!(sample.measurements),
        to_string(sample.status),
        sample.created_at
      ])
    end)
    {:ok, state}
  end

  def list(filters, %{conn: conn} = state) do
    query = build_query(filters)
    result = Postgrex.query!(conn, query, [])
    samples = parse_results(result.rows)
    {:ok, samples, state}
  end

  def cleanup(%{conn: conn}) do
    GenServer.stop(conn)
    :ok
  end
end
```

## Alternatives Considered

### 1. Repository Pattern
```elixir
defmodule Forge.Repository do
  def insert(sample), do: ...
  def get(id), do: ...
  def all(query), do: ...
end
```
**Rejected**: Too opinionated, doesn't fit all storage models (streams, write-only).

### 2. Ecto Integration
Use Ecto schemas and changesets.
**Rejected**: Heavy dependency, not all backends are databases.

### 3. Protocol-based Design
```elixir
defprotocol Forge.Storage do
  def store(backend, samples)
end
```
**Rejected**: Can't maintain state across calls, complicates lifecycle.

### 4. Process-based Storage
Each backend is a GenServer.
**Rejected**: Unnecessary complexity for simple backends, harder to test.

### 5. Callback-free, Module Functions
Just define functions without behaviour.
**Rejected**: No compile-time guarantees, harder to document.

## References
- ETS documentation: https://www.erlang.org/doc/man/ets.html
- Ecto Repository: https://hexdocs.pm/ecto/Ecto.Repo.html
- GenServer patterns: https://hexdocs.pm/elixir/GenServer.html
