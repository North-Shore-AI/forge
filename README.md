<div align="center">

# Forge

<svg width="140" height="140" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Main gradient for hexagon -->
    <linearGradient id="hexGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ff6b35;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#f7931e;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#ff4500;stop-opacity:1" />
    </linearGradient>

    <!-- Inner glow gradient -->
    <radialGradient id="innerGlow" cx="50%" cy="50%">
      <stop offset="0%" style="stop-color:#fff4e6;stop-opacity:0.9" />
      <stop offset="40%" style="stop-color:#ffb347;stop-opacity:0.6" />
      <stop offset="100%" style="stop-color:#ff6b35;stop-opacity:0" />
    </radialGradient>

    <!-- Outer glow -->
    <radialGradient id="outerGlow" cx="50%" cy="50%">
      <stop offset="70%" style="stop-color:#ff4500;stop-opacity:0" />
      <stop offset="85%" style="stop-color:#ff6b35;stop-opacity:0.3" />
      <stop offset="100%" style="stop-color:#ff4500;stop-opacity:0" />
    </radialGradient>

    <!-- Anvil gradient -->
    <linearGradient id="anvilGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4a4a4a;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#6a6a6a;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#3a3a3a;stop-opacity:1" />
    </linearGradient>

    <!-- Fire gradient -->
    <linearGradient id="fireGrad" x1="0%" y1="100%" x2="0%" y2="0%">
      <stop offset="0%" style="stop-color:#ff4500;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#ffa500;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#ffeb3b;stop-opacity:0.8" />
    </linearGradient>

    <!-- Metallic highlight -->
    <linearGradient id="metallic" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#ffffff;stop-opacity:0" />
      <stop offset="50%" style="stop-color:#ffffff;stop-opacity:0.6" />
      <stop offset="100%" style="stop-color:#ffffff;stop-opacity:0" />
    </linearGradient>

    <!-- Heat shimmer -->
    <radialGradient id="heatShimmer" cx="50%" cy="60%">
      <stop offset="0%" style="stop-color:#ffeb3b;stop-opacity:0.7" />
      <stop offset="50%" style="stop-color:#ffa500;stop-opacity:0.3" />
      <stop offset="100%" style="stop-color:#ff4500;stop-opacity:0" />
    </radialGradient>

    <!-- Shadow -->
    <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="3"/>
      <feOffset dx="0" dy="2" result="offsetblur"/>
      <feComponentTransfer>
        <feFuncA type="linear" slope="0.3"/>
      </feComponentTransfer>
      <feMerge>
        <feMergeNode/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>

    <!-- Glow effect -->
    <filter id="glow">
      <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <!-- Outer glow background -->
  <circle cx="100" cy="100" r="90" fill="url(#outerGlow)" opacity="0.6"/>

  <!-- Main hexagon outline -->
  <polygon points="100,20 170,55 170,130 100,165 30,130 30,55"
           fill="url(#hexGrad)"
           stroke="#d64500"
           stroke-width="2"
           filter="url(#shadow)"/>

  <!-- Inner hexagon with geometric pattern -->
  <polygon points="100,30 160,60 160,125 100,155 40,125 40,60"
           fill="none"
           stroke="#ff8c42"
           stroke-width="1.5"
           opacity="0.7"/>

  <!-- Intricate geometric lines - creating depth -->
  <line x1="100" y1="20" x2="100" y2="40" stroke="#ff8c42" stroke-width="1" opacity="0.5"/>
  <line x1="170" y1="55" x2="155" y2="65" stroke="#ff8c42" stroke-width="1" opacity="0.5"/>
  <line x1="170" y1="130" x2="155" y2="120" stroke="#ff8c42" stroke-width="1" opacity="0.5"/>
  <line x1="100" y1="165" x2="100" y2="145" stroke="#ff8c42" stroke-width="1" opacity="0.5"/>
  <line x1="30" y1="130" x2="45" y2="120" stroke="#ff8c42" stroke-width="1" opacity="0.5"/>
  <line x1="30" y1="55" x2="45" y2="65" stroke="#ff8c42" stroke-width="1" opacity="0.5"/>

  <!-- Heat shimmer effect -->
  <circle cx="100" cy="110" r="40" fill="url(#heatShimmer)" opacity="0.4"/>

  <!-- Anvil base -->
  <path d="M 65,115 L 135,115 L 130,125 L 70,125 Z"
        fill="url(#anvilGrad)"
        stroke="#2a2a2a"
        stroke-width="1.5"
        filter="url(#shadow)"/>

  <!-- Anvil top surface -->
  <ellipse cx="100" cy="115" rx="35" ry="8"
           fill="url(#metallic)"
           stroke="#2a2a2a"
           stroke-width="1"/>

  <!-- Anvil body -->
  <path d="M 75,115 L 125,115 L 125,110 L 75,110 Z"
        fill="#5a5a5a"
        stroke="#2a2a2a"
        stroke-width="1"/>

  <!-- Anvil horn (left side detail) -->
  <path d="M 75,110 L 70,108 L 70,112 L 75,115 Z"
        fill="#4a4a4a"
        stroke="#2a2a2a"
        stroke-width="0.5"/>

  <!-- Central fire flames - stylized -->
  <g filter="url(#glow)">
    <!-- Central flame -->
    <path d="M 100,95 Q 95,85 100,75 Q 105,85 100,95 Z"
          fill="url(#fireGrad)"
          opacity="0.9"/>

    <!-- Left flame -->
    <path d="M 88,100 Q 85,92 88,84 Q 92,92 88,100 Z"
          fill="url(#fireGrad)"
          opacity="0.8"/>

    <!-- Right flame -->
    <path d="M 112,100 Q 108,92 112,84 Q 115,92 112,100 Z"
          fill="url(#fireGrad)"
          opacity="0.8"/>

    <!-- Small accent flames -->
    <path d="M 95,98 Q 93,93 95,88 Q 97,93 95,98 Z"
          fill="#ffeb3b"
          opacity="0.7"/>
    <path d="M 105,98 Q 103,93 105,88 Q 107,93 105,98 Z"
          fill="#ffeb3b"
          opacity="0.7"/>
  </g>

  <!-- Sparks and embers -->
  <circle cx="78" cy="78" r="1.5" fill="#ffeb3b" opacity="0.8"/>
  <circle cx="122" cy="82" r="1.2" fill="#ffa500" opacity="0.9"/>
  <circle cx="85" cy="68" r="1" fill="#ffeb3b" opacity="0.7"/>
  <circle cx="115" cy="72" r="1.3" fill="#ff8c42" opacity="0.8"/>
  <circle cx="92" cy="62" r="0.8" fill="#ffeb3b" opacity="0.6"/>
  <circle cx="108" cy="65" r="1" fill="#ffa500" opacity="0.7"/>

  <!-- Geometric pattern overlay - sacred geometry inspired -->
  <g opacity="0.15" stroke="#ffffff" stroke-width="0.5" fill="none">
    <!-- Inner sacred geometry circles -->
    <circle cx="100" cy="92.5" r="25"/>
    <circle cx="100" cy="92.5" r="18"/>
    <circle cx="100" cy="92.5" r="12"/>

    <!-- Connecting lines creating star pattern -->
    <line x1="100" y1="67.5" x2="100" y2="117.5"/>
    <line x1="78.35" y1="80" x2="121.65" y2="105"/>
    <line x1="78.35" y1="105" x2="121.65" y2="80"/>
    <line x1="75" y1="92.5" x2="125" y2="92.5"/>
    <line x1="87.5" y1="71.65" x2="112.5" y2="113.35"/>
    <line x1="87.5" y1="113.35" x2="112.5" y2="71.65"/>
  </g>

  <!-- Forge maker's mark - stylized "F" -->
  <g opacity="0.4" fill="#2a2a2a" stroke="none">
    <path d="M 95,135 L 95,145 L 93,145 L 93,135 Z"/>
    <path d="M 93,135 L 102,135 L 102,137 L 93,137 Z"/>
    <path d="M 93,139 L 99,139 L 99,141 L 93,141 Z"/>
  </g>

  <!-- Inner glow overlay -->
  <circle cx="100" cy="85" r="35" fill="url(#innerGlow)" opacity="0.3"/>

  <!-- Highlight edge on hexagon -->
  <line x1="100" y1="20" x2="170" y2="55"
        stroke="url(#metallic)"
        stroke-width="2"
        opacity="0.3"/>
  <line x1="30" y1="55" x2="100" y2="20"
        stroke="url(#metallic)"
        stroke-width="2"
        opacity="0.2"/>

  <!-- Corner detail ornaments -->
  <g opacity="0.3" fill="none" stroke="#ffffff" stroke-width="0.8">
    <circle cx="100" cy="25" r="3"/>
    <circle cx="165" cy="57.5" r="3"/>
    <circle cx="165" cy="127.5" r="3"/>
    <circle cx="100" cy="160" r="3"/>
    <circle cx="35" cy="127.5" r="3"/>
    <circle cx="35" cy="57.5" r="3"/>
  </g>
</svg>

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
