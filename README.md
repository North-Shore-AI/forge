<div align="center">

# Forge

<img src="assets/forge.svg" alt="Forge Logo" width="280"/>

</div>

<div align="center">

**A domain-agnostic sample factory library for generating, transforming, and computing measurements on arbitrary samples in Elixir.**

</div>

## Purpose

Forge provides a flexible, composable framework for working with sample data across any domain. Whether you're processing scientific measurements, user analytics, sensor data, or synthetic datasets, Forge offers:

- **Sample Generation**: Create samples from static lists or dynamic generators
- **Pipeline Transformation**: Chain together stages to transform and enrich samples
- **Measurement Computation**: Calculate metrics and measurements on samples (sync/async)
- **Storage Backends**: Persist samples with pluggable storage implementations
- **Lifecycle Management**: Track samples through their lifecycle states

## Core Abstractions

### Source
Behaviours for generating or providing samples to the pipeline. Implementations include:
- `Forge.Source.Static` - Samples from a static list
- `Forge.Source.Generator` - Samples from a generator function

### Pipeline
Defines a series of stages that process samples. Pipelines are configured with:
- Source configuration
- Ordered stages for transformation
- Measurement definitions
- Storage backend

### Stage
Behaviours for transforming samples as they move through the pipeline. Stages are composable and can:
- Filter samples
- Transform sample data
- Enrich samples with additional information
- Change sample status

### Measurement
Behaviours for computing metrics and measurements on samples. Can be executed:
- Synchronously during pipeline execution
- Asynchronously for expensive computations

### Sample
Core data structure representing a sample:
```elixir
%Forge.Sample{
  id: "unique-id",
  pipeline: :my_pipeline,
  data: %{key: "value"},
  measurements: %{},
  status: :pending,
  created_at: ~U[2025-01-01 00:00:00Z],
  measured_at: nil
}
```

Lifecycle states: `:pending` -> `:measured` -> `:ready` -> `:labeled` or `:skipped`

### Storage
Behaviours for persisting samples. Implementations include:
- `Forge.Storage.ETS` - In-memory ETS-based storage
- Custom backends (database, file system, cloud storage, etc.)

## Installation

Add `forge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:forge, "~> 0.1.0"}
  ]
end
```

## Usage Examples

### Basic Pipeline

```elixir
# Define a simple pipeline
defmodule MyApp.Pipeline do
  use Forge.Pipeline

  pipeline :data_processing do
    source Forge.Source.Static, data: [
      %{value: 10},
      %{value: 20},
      %{value: 30}
    ]

    stage MyApp.Stages.Normalize
    stage MyApp.Stages.Validate

    measurement MyApp.Measurements.Mean
    measurement MyApp.Measurements.StdDev

    storage Forge.Storage.ETS, table: :samples
  end
end

# Run the pipeline
{:ok, runner} = Forge.Runner.start_link(pipeline: MyApp.Pipeline, name: :data_processing)
samples = Forge.Runner.run(runner)
```

### Custom Stage

```elixir
defmodule MyApp.Stages.Normalize do
  @behaviour Forge.Stage

  @impl true
  def process(sample) do
    normalized_value = sample.data.value / 100.0
    data = Map.put(sample.data, :normalized, normalized_value)
    {:ok, %{sample | data: data}}
  end
end
```

### Custom Measurement

```elixir
defmodule MyApp.Measurements.Mean do
  @behaviour Forge.Measurement

  @impl true
  def compute(samples) do
    values = Enum.map(samples, & &1.data.value)
    mean = Enum.sum(values) / length(values)
    {:ok, %{mean: mean}}
  end

  @impl true
  def async?(), do: false
end
```

### Generator Source

```elixir
defmodule MyApp.Pipeline do
  use Forge.Pipeline

  pipeline :generated_data do
    source Forge.Source.Generator,
      count: 1000,
      generator: fn index ->
        %{value: :rand.uniform() * 100, index: index}
      end

    stage MyApp.Stages.Filter
    measurement MyApp.Measurements.Distribution
    storage Forge.Storage.ETS, table: :generated_samples
  end
end
```

## API Documentation

### Main API (`Forge`)

```elixir
# Create a sample
Forge.create_sample(pipeline: :my_pipeline, data: %{key: "value"})

# Process samples through a pipeline
Forge.run_pipeline(:my_pipeline, samples)

# Compute measurements
Forge.compute_measurements(samples, measurements)

# Store samples
Forge.store_samples(samples, storage_backend)
```

### Pipeline Definition

Use the `Forge.Pipeline` behaviour to define your pipelines:

```elixir
defmodule MyPipeline do
  use Forge.Pipeline

  pipeline :name do
    source SourceModule, opts
    stage StageModule
    measurement MeasurementModule
    storage StorageModule, opts
  end
end
```

### Running Pipelines

The `Forge.Runner` GenServer executes pipelines:

```elixir
# Start a runner
{:ok, pid} = Forge.Runner.start_link(pipeline: MyPipeline, name: :my_pipeline)

# Run the pipeline
samples = Forge.Runner.run(pid)

# Get status
status = Forge.Runner.status(pid)
```

## Architecture Decisions

See the [Architecture Decision Records (ADRs)](docs/adrs/) for detailed design decisions:

- [ADR-001: Source Behaviour Design](docs/adrs/001-source-behaviour-design.md)
- [ADR-002: Pipeline Configuration DSL](docs/adrs/002-pipeline-configuration-dsl.md)
- [ADR-003: Stage Composition Model](docs/adrs/003-stage-composition-model.md)
- [ADR-004: Measurement Computation Strategy](docs/adrs/004-measurement-computation-strategy.md)
- [ADR-005: Storage Behaviour and Backends](docs/adrs/005-storage-behaviour-and-backends.md)
- [ADR-006: Sample Lifecycle States](docs/adrs/006-sample-lifecycle-states.md)

## Development

```bash
# Get dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Generate documentation
mix docs
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Copyright 2025 North-Shore-AI

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the LICENSE file.
