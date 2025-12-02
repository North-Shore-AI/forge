# ADR-002: Pipeline Configuration DSL

## Status
Accepted

## Context
Pipelines are the core abstraction in Forge, defining how samples flow from source through stages to storage. We need a configuration approach that:

1. Is declarative and easy to understand
2. Provides compile-time validation where possible
3. Allows flexible composition of stages and measurements
4. Integrates well with Elixir's macro system
5. Supports multiple pipelines in a single module
6. Enables runtime introspection of pipeline configuration

## Decision

We will implement a macro-based DSL using `use Forge.Pipeline` that provides a `pipeline/2` macro for defining pipelines.

### DSL Design

```elixir
defmodule MyApp.Pipelines do
  use Forge.Pipeline

  pipeline :data_processing do
    source Forge.Source.Static, data: [%{value: 1}]

    stage MyApp.Stages.Normalize
    stage MyApp.Stages.Validate, strict: true

    measurement MyApp.Measurements.Mean
    measurement MyApp.Measurements.StdDev, async: true

    storage Forge.Storage.ETS, table: :samples
  end

  pipeline :streaming do
    source MyApp.Source.Stream, topic: "data"
    stage MyApp.Stages.Filter
    storage Forge.Storage.ETS, table: :stream_samples
  end
end
```

### Macro Implementation

The `pipeline/2` macro will:
1. Collect configuration into a pipeline struct
2. Define a function `__pipeline__/1` that returns config by name
3. Validate that required components are present
4. Store configuration at compile time

### Pipeline Structure

```elixir
defmodule Forge.Pipeline.Config do
  defstruct [
    :name,
    :source_module,
    :source_opts,
    stages: [],
    measurements: [],
    :storage_module,
    :storage_opts
  ]
end
```

### DSL Keywords

- **source** (required): Specifies the source module and options
- **stage** (optional, multiple): Adds a stage to the pipeline
- **measurement** (optional, multiple): Adds a measurement
- **storage** (optional): Specifies storage backend

### Introspection API

```elixir
# Get pipeline configuration
config = MyApp.Pipelines.__pipeline__(:data_processing)

# List all pipelines in a module
pipelines = MyApp.Pipelines.__pipelines__()
```

## Consequences

### Positive
- Declarative syntax is clear and readable
- Compile-time macro expansion enables validation
- Easy to add new configuration options
- Familiar pattern for Elixir developers (like Ecto schemas)
- Configuration is stored in module attributes for introspection
- Multiple pipelines can coexist in one module

### Negative
- Requires understanding macros for advanced customization
- Error messages from macros can be cryptic
- Runtime configuration changes require recompilation
- Additional complexity in the library code

### Neutral
- Configuration is static at compile time
- Order of stages matters (sequential processing)
- No built-in conditional stage execution

## Implementation Details

### Macro Expansion

```elixir
# This DSL code:
pipeline :example do
  source MySource, opt: 1
  stage MyStage
  storage MyStorage
end

# Expands to:
def __pipeline__(:example) do
  %Forge.Pipeline.Config{
    name: :example,
    source_module: MySource,
    source_opts: [opt: 1],
    stages: [{MyStage, []}],
    measurements: [],
    storage_module: MyStorage,
    storage_opts: []
  }
end
```

### Compile-time Validation

The macro will validate:
- Source is specified (required)
- Source module exists and implements behaviour
- Stage modules implement Forge.Stage
- Measurement modules implement Forge.Measurement
- Storage module implements Forge.Storage (if specified)

## Examples

### Minimal Pipeline
```elixir
pipeline :minimal do
  source Forge.Source.Static, data: [%{x: 1}]
end
```

### Complex Pipeline
```elixir
pipeline :ml_preprocessing do
  source MyApp.DatasetSource,
    path: "data/train.csv",
    batch_size: 100

  stage MyApp.Stages.ParseCSV
  stage MyApp.Stages.Normalize, method: :z_score
  stage MyApp.Stages.Augment, factor: 2
  stage MyApp.Stages.Shuffle, seed: 42

  measurement MyApp.Measurements.Stats
  measurement MyApp.Measurements.Distribution, bins: 20

  storage Forge.Storage.Disk,
    path: "data/processed",
    format: :parquet
end
```

## Alternatives Considered

### 1. Keyword List Configuration
```elixir
def config do
  [
    source: {MySource, opt: 1},
    stages: [MyStage1, MyStage2],
    storage: {MyStorage, []}
  ]
end
```
**Rejected**: No compile-time validation, less readable, no IDE support.

### 2. Struct-based Configuration
```elixir
%Pipeline{
  source: %{module: MySource, opts: []},
  stages: [%{module: MyStage}]
}
```
**Rejected**: Verbose, no validation, no compile-time benefits.

### 3. Builder Pattern
```elixir
Pipeline.new()
|> Pipeline.source(MySource, opt: 1)
|> Pipeline.stage(MyStage)
|> Pipeline.storage(MyStorage)
```
**Rejected**: Runtime-only, can't leverage compile-time validation.

### 4. Configuration Files (YAML/JSON)
External configuration files for pipelines.
**Rejected**: Lose compile-time validation, type safety, and Elixir tooling integration.

## References
- Ecto Schema DSL: https://hexdocs.pm/ecto/Ecto.Schema.html
- Phoenix Router DSL: https://hexdocs.pm/phoenix/routing.html
- Elixir Macros: https://hexdocs.pm/elixir/Macro.html
