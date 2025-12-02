# ADR-006: Sample Lifecycle States

## Status
Accepted

## Context
Samples in Forge flow through a pipeline and undergo various transformations and measurements. We need a way to track where each sample is in its lifecycle to:

1. Enable filtering and querying by processing state
2. Provide visibility into pipeline progress
3. Support conditional processing based on current state
4. Track which samples have completed processing
5. Identify samples that were filtered or skipped
6. Distinguish between different completion outcomes

The state model should be:
- Simple and easy to understand
- Sufficient for common use cases
- Extensible for custom workflows
- Self-documenting through naming

## Decision

We will implement a finite set of lifecycle states as atoms in the `Forge.Sample` struct. The `status` field will use the following states:

### Lifecycle States

```elixir
@type status :: :pending | :measured | :ready | :labeled | :skipped
```

**:pending**
- Initial state when sample is created
- Sample has not been processed yet
- No measurements computed
- Data in original form from source

**:measured**
- Sample has completed measurement computation
- All synchronous measurements have been computed
- Measurements map is populated
- `measured_at` timestamp is set
- Sample is ready for further processing

**:ready**
- Sample has completed all pipeline processing
- All stages have been applied
- All measurements completed
- Sample is in final form
- Ready for labeling or consumption

**:labeled**
- Sample has been labeled/annotated (optional state)
- Used in ML/data annotation workflows
- Indicates human or automated labeling complete
- Terminal state for labeled workflows

**:skipped**
- Sample was filtered out during processing
- A stage returned `{:skip, reason}`
- Sample will not continue through pipeline
- Terminal state for skipped samples

### State Transitions

```
:pending → :measured → :ready → :labeled
    ↓
:skipped (can happen from any state)
```

**Valid Transitions:**
- `:pending` → `:measured` (after measurements)
- `:pending` → `:skipped` (filtered before measurement)
- `:measured` → `:ready` (after all stages)
- `:measured` → `:skipped` (filtered after measurement)
- `:ready` → `:labeled` (after labeling)
- `:ready` → `:skipped` (marked as invalid)
- Any state → `:skipped` (filtered out)

### Sample Structure

```elixir
defmodule Forge.Sample do
  @type t :: %__MODULE__{
    id: String.t(),
    pipeline: atom(),
    data: map(),
    measurements: map(),
    status: :pending | :measured | :ready | :labeled | :skipped,
    created_at: DateTime.t(),
    measured_at: DateTime.t() | nil
  }

  defstruct [
    :id,
    :pipeline,
    :data,
    measurements: %{},
    status: :pending,
    :created_at,
    measured_at: nil
  ]
end
```

### Runner State Management

The pipeline runner will update sample status at appropriate points:

```elixir
# After source generates sample
%Sample{status: :pending, created_at: DateTime.utc_now()}

# After measurements computed
%Sample{status: :measured, measured_at: DateTime.utc_now()}

# After all stages complete
%Sample{status: :ready}

# If stage filters sample
%Sample{status: :skipped}
```

## Consequences

### Positive
- Clear, semantic state names
- Simple state machine with well-defined transitions
- Easy to filter and query samples by status
- Supports common workflows (measurement, labeling)
- Skipped state provides visibility into filtered samples
- Status progression is intuitive

### Negative
- Limited set of states may not fit all use cases
- No built-in support for error states
- No sub-states or detailed progress tracking
- Custom states require extending the type

### Neutral
- States are domain-agnostic
- No automatic state validation (trust stages to set correctly)
- Timestamps only for key transitions (created, measured)
- Status transitions are convention, not enforced

## Implementation Details

### Status Helpers

```elixir
defmodule Forge.Sample do
  def pending?(sample), do: sample.status == :pending
  def measured?(sample), do: sample.status == :measured
  def ready?(sample), do: sample.status == :ready
  def labeled?(sample), do: sample.status == :labeled
  def skipped?(sample), do: sample.status == :skipped

  def mark_measured(sample) do
    %{sample | status: :measured, measured_at: DateTime.utc_now()}
  end

  def mark_ready(sample) do
    %{sample | status: :ready}
  end

  def mark_labeled(sample) do
    %{sample | status: :labeled}
  end

  def mark_skipped(sample) do
    %{sample | status: :skipped}
  end
end
```

### Pipeline Integration

```elixir
defp process_sample(sample, stages) do
  # Start as pending
  sample = %{sample | status: :pending}

  # Apply stages
  case apply_stages(sample, stages) do
    {:ok, processed} ->
      %{processed | status: :ready}

    {:skip, _reason} ->
      %{sample | status: :skipped}
  end
end

defp compute_measurements(samples, measurements) do
  Enum.map(samples, fn sample ->
    results = run_measurements(sample, measurements)
    %{sample |
      status: :measured,
      measured_at: DateTime.utc_now(),
      measurements: Map.merge(sample.measurements, results)
    }
  end)
end
```

### Filtering by Status

```elixir
# Get all ready samples
ready_samples = Enum.filter(samples, &Sample.ready?/1)

# Get processing completion rate
total = length(samples)
ready = Enum.count(samples, &Sample.ready?/1)
skipped = Enum.count(samples, &Sample.skipped?/1)
completion_rate = ready / total

# Storage queries
Storage.list([status: :ready], state)
Storage.list([status: :skipped], state)
```

## Examples

### Basic Lifecycle
```elixir
# Sample created from source
sample = %Sample{
  id: "123",
  pipeline: :my_pipeline,
  data: %{value: 42},
  status: :pending,
  created_at: DateTime.utc_now()
}

# After measurements
sample = Sample.mark_measured(sample)
# %{status: :measured, measured_at: ~U[...]}

# After stages complete
sample = Sample.mark_ready(sample)
# %{status: :ready}

# If labeled
sample = Sample.mark_labeled(sample)
# %{status: :labeled}
```

### Filtering Stage
```elixir
defmodule ValidateStage do
  def process(sample) do
    if valid?(sample.data) do
      {:ok, sample}
    else
      # Sample will be marked as skipped
      {:skip, :validation_failed}
    end
  end
end
```

### Status-based Processing
```elixir
defmodule ConditionalStage do
  def process(sample) do
    case sample.status do
      :measured ->
        # Additional processing for measured samples
        {:ok, enhance(sample)}

      _ ->
        # Skip if not measured
        {:ok, sample}
    end
  end
end
```

### Monitoring Pipeline Progress
```elixir
defmodule PipelineMonitor do
  def report(samples) do
    stats = Enum.group_by(samples, & &1.status)

    %{
      total: length(samples),
      pending: length(Map.get(stats, :pending, [])),
      measured: length(Map.get(stats, :measured, [])),
      ready: length(Map.get(stats, :ready, [])),
      labeled: length(Map.get(stats, :labeled, [])),
      skipped: length(Map.get(stats, :skipped, [])),
      completion_rate: calculate_completion_rate(stats)
    }
  end
end
```

## Alternatives Considered

### 1. Free-form Status Strings
```elixir
status: String.t()
```
**Rejected**: No type safety, inconsistent naming, hard to query, prone to typos.

### 2. Numeric Status Codes
```elixir
status: 0..100
```
**Rejected**: Not self-documenting, requires lookup table, unclear semantics.

### 3. Complex State Machine
Multiple state fields with detailed tracking:
```elixir
%{
  processing_state: :running,
  measurement_state: :complete,
  validation_state: :pending
}
```
**Rejected**: Over-engineered for most use cases, complex to manage.

### 4. Extensible State with Metadata
```elixir
status: atom()
status_metadata: map()
```
**Rejected**: Too flexible, loses standardization, harder to query.

### 5. No Status Field
Track state through separate fields:
```elixir
%{measured_at: nil | DateTime.t(), processed: boolean()}
```
**Rejected**: Unclear lifecycle, hard to query, no semantic meaning.

### 6. Process State
```elixir
:not_started | :processing | :complete | :failed
```
**Rejected**: Too generic, doesn't capture domain semantics (measurement, labeling).

## Future Considerations

### Custom States
For applications needing additional states:
```elixir
defmodule CustomSample do
  use Forge.Sample

  @type status :: Forge.Sample.status() | :verified | :published
end
```

### State Metadata
Store additional state information:
```elixir
%Sample{
  status: :skipped,
  data: %{
    ...
    _forge_metadata: %{
      skip_reason: :validation_failed,
      skip_stage: MyStage,
      skipped_at: ~U[...]
    }
  }
}
```

### Audit Trail
Track all state transitions:
```elixir
%Sample{
  ...
  _state_history: [
    {:pending, ~U[2025-01-01 10:00:00Z]},
    {:measured, ~U[2025-01-01 10:00:05Z]},
    {:ready, ~U[2025-01-01 10:00:10Z]}
  ]
}
```

## References
- Finite State Machines: https://en.wikipedia.org/wiki/Finite-state_machine
- Ecto Enum: https://hexdocs.pm/ecto/Ecto.Enum.html
- State pattern: https://en.wikipedia.org/wiki/State_pattern
