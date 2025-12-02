<div align="center">

# Forge

<img src="assets/forge.svg" alt="Forge Logo" width="392"/>

**Domain-agnostic sample factory for building repeatable data pipelines in Elixir.**

</div>

Forge helps you generate samples, apply staged transformations, compute measurements, and persist results for dataset creation, evaluation harnesses, enrichment jobs, and analytics workflows.

## Highlights
- Pipeline DSL that wires together sources, stages, measurements, and storage backends
- Two execution modes: a GenServer runner for simple batch runs and a streaming runner with backpressure and async stages
- Resilient stage execution with retry policies, error classification, and DLQ marking
- Measurement orchestration with caching, versioning, dependency resolution, and batch/async compute
- Pluggable storage (ETS, Postgres) plus content-addressed artifact storage (local filesystem, S3 stub)
- Built-in telemetry events, metric helpers, and optional OpenTelemetry tracing
- Human-in-the-loop bridge for publishing samples to Anvil with mock/direct/http adapters
- Deterministic manifests for reproducibility and drift detection

## Core Building Blocks
- **Samples**: `Forge.Sample` carries `id`, `pipeline`, `data`, `measurements`, status (`:pending`, `:measured`, `:ready`, `:labeled`, `:skipped`, `:dlq`), and timestamps.
- **Pipelines**: `use Forge.Pipeline` to declare `pipeline/2` blocks with `source`, `stage`, `measurement`, and `storage` entries. Introspection helpers: `__pipeline__/1`, `__pipelines__/0`.
- **Sources**: Behaviour-driven inputs; built-ins include `Forge.Source.Static` (fixed list) and `Forge.Source.Generator` (function-based). Implement `init/1`, `fetch/1`, `cleanup/1` for custom data feeds.
- **Stages**: `Forge.Stage` behaviour for per-sample transforms. Optional `async?/0`, `concurrency/0`, and `timeout/0` guide execution. `Forge.Stage.Executor` applies stages with `Forge.RetryPolicy` and `Forge.ErrorClassifier` to decide retries vs. DLQ.
- **Measurements**: `Forge.Measurement` behaviour with `key/0`, `version/0`, and `compute/1`, plus optional async, batch, dependencies, and timeouts. `Forge.Measurement.Orchestrator` provides cached, versioned measurement storage with dependency ordering and batch execution.
- **Manifests**: `Forge.Manifest` and `Forge.Manifest.Hash` capture deterministic hashes of pipeline configuration, git SHA, and secret usage for reproducibility.
- **Human-in-the-loop**: `Forge.AnvilBridge` adapters (Mock, Direct stub, HTTP stub) publish samples to Anvil and sync labels; convert samples with `sample_to_dto/2`.

## Runners
- **GenServer runner (`Forge.Runner`)**: Pulls all samples from the source, applies stages with retry policies, computes measurements (sync and async), optionally persists via storage, and emits telemetry.
- **Streaming runner (`Forge.Runner.Streaming`)**: Lazily processes samples with optional async stages and bounded concurrency, suitable for large datasets and backpressure-aware consumers.

### Quick Start

Define a pipeline:

```elixir
defmodule MyApp.Pipelines do
  use Forge.Pipeline

  pipeline :narratives do
    source Forge.Source.Generator,
      count: 3,
      generator: fn idx -> %{id: idx, text: "narrative-#{idx}"} end

    stage MyApp.NormalizeStage
    measurement MyApp.Measurements.Length
    storage Forge.Storage.ETS, table: :narrative_samples
  end
end
```

Run it with the GenServer runner:

```elixir
{:ok, runner} =
  Forge.Runner.start_link(pipeline_module: MyApp.Pipelines, pipeline_name: :narratives)

samples = Forge.Runner.run(runner)
Forge.Runner.stop(runner)
```

Stream it with backpressure instead:

```elixir
stream =
  MyApp.Pipelines.__pipeline__(:narratives)
  |> Forge.Runner.Streaming.run(concurrency: 8)

stream |> Enum.take(10)
```

## Measurements & Orchestration
- Implement measurement modules with unique `key/0` and `version/0`. Opt into batching via `batch_capable?/0` and `compute_batch/1` or mark `async?/0` for fire-and-forget.
- `Forge.Measurement.Orchestrator` caches results in `forge_measurements` (Ecto) and supports dependency graphs:

```elixir
{:ok, :computed, value} =
  Forge.Measurement.Orchestrator.measure_sample(sample_id, MyApp.Measurements.Length, [])
```

## Persistence & Artifacts
- **Sample storage**: `Forge.Storage.ETS` (fast, in-memory) and `Forge.Storage.Postgres` (durable, with lineage via `forge_samples`, stage executions, measurements). Database migrations live in `priv/repo/migrations`; run `mix forge.setup` to create and migrate.
- **Artifacts**: `Forge.ArtifactStorage.Local` stores blobs content-addressed on disk and emits telemetry; `Forge.ArtifactStorage.S3` provides the interface for a future ExAws-backed adapter.

## Observability
- Telemetry events cover pipelines, stages, measurements, storage, and DLQ moves (`Forge.Telemetry`).
- Prebuilt metric specs are available in `Forge.Telemetry.Metrics`.
- Optional OpenTelemetry tracing via `Forge.Telemetry.OTel` when configured.
- See `docs/telemetry.md` for event and metric details.

## Anvil Integration
- Configure the Anvil bridge adapter via `config :forge, :anvil_bridge_adapter, Forge.AnvilBridge.Mock` (default), `Direct`, or `HTTP`.
- Publish samples or batches with `Forge.AnvilBridge.publish_sample/2` and `publish_batch/2`; fetch or sync labels with `get_labels/1` and `sync_labels/2`.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:forge_ex, "~> 0.1.0"}
  ]
end
```

For Postgres-backed features (storage, measurement orchestrator), configure `Forge.Repo` and run the provided migrations. Defaults use `postgres/postgres` on localhost; override via environment or config.

## Development

```bash
mix deps.get            # Install dependencies
mix forge.setup         # Create & migrate Postgres schemas (if using Repo-backed features)
mix test                # Run the test suite (sets up DB via alias)
mix docs                # Generate ExDoc documentation
```

## License

MIT License © 2024-2025 North-Shore-AI
