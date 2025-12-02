# ADR-008: Anvil Integration

## Status
Accepted

## Context

Anvil is North-Shore-AI's human-in-the-loop labeling platform. Forge generates samples; Anvil manages labeling queues, annotations, and quality control. The two systems must integrate seamlessly:

**Forge's responsibilities**:
- Generate samples (narratives, claims, documents)
- Compute measurements (embeddings, quality scores, topology features)
- Store samples durably with lineage tracking

**Anvil's responsibilities**:
- Queue samples for human review
- Capture labels (contradiction, entailment, neutral)
- Track annotator agreement, quality metrics
- Export labeled datasets for training

**Integration requirements**:

1. **Sample resolution**: Anvil must reference Forge samples by UUID (foreign key relationship)
2. **DTO conversion**: Transform Forge samples into Anvil-ready format (title, body, metadata)
3. **Bidirectional sync**: Anvil labels flow back to Forge (enrich samples with annotations)
4. **Shared infrastructure**: Single Postgres cluster, separate schemas (cost, consistency)
5. **Incremental export**: Stream new samples to Anvil queues (not batch uploads)
6. **Measurement availability**: Anvil UI displays Forge measurements alongside samples (e.g., "Embedding distance: 0.87")

**Current state**:
- Anvil and Forge are separate repos with no integration
- Manual CSV export/import workflow (brittle, slow)
- No shared data model (sample IDs not synchronized)

## Decision

### 1. Shared Postgres Cluster, Separate Schemas

Deploy Forge and Anvil on same Postgres instance with schema isolation:

```sql
-- Forge schema
CREATE SCHEMA forge;

CREATE TABLE forge.samples (
  id UUID PRIMARY KEY,
  pipeline_id UUID NOT NULL,
  data JSONB,
  status VARCHAR(50),
  created_at TIMESTAMPTZ
);

-- Anvil schema
CREATE SCHEMA anvil;

CREATE TABLE anvil.labeling_jobs (
  id UUID PRIMARY KEY,
  sample_id UUID NOT NULL,  -- references forge.samples(id)
  queue_name VARCHAR(255),
  title TEXT,
  body TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ
);

-- Cross-schema foreign key
ALTER TABLE anvil.labeling_jobs
ADD CONSTRAINT fk_forge_sample
FOREIGN KEY (sample_id) REFERENCES forge.samples(id)
ON DELETE CASCADE;

CREATE TABLE anvil.annotations (
  id UUID PRIMARY KEY,
  labeling_job_id UUID REFERENCES anvil.labeling_jobs(id),
  label VARCHAR(100),
  annotator_id UUID,
  confidence FLOAT,
  created_at TIMESTAMPTZ
);
```

**Benefits**:
- **Referential integrity**: FK constraint prevents orphaned labeling jobs
- **Cost savings**: Single RDS instance vs two (~$3k/year savings)
- **Consistency**: ACID transactions across Forge + Anvil (e.g., atomic sample export)
- **Ops simplicity**: One backup/restore, one monitoring stack

**Schema isolation**:
- Separate Ecto repos (`Forge.Repo`, `Anvil.Repo`)
- Independent connection pools (10 for Forge, 20 for Anvil)
- No cross-schema queries in application code (use ForgeBridge)

### 2. ForgeBridge Module

Adapter for Forge ↔ Anvil communication:

```elixir
defmodule ForgeBridge do
  @moduledoc """
  Integration layer between Forge (sample factory) and Anvil (labeling platform).
  Handles sample export, DTO conversion, and label synchronization.
  """

  alias Forge.Storage.Postgres, as: ForgeStorage
  alias Anvil.Queue, as: AnvilQueue

  @doc """
  Export Forge samples to Anvil labeling queue.

  ## Options
  - `:queue_name` - Target Anvil queue (required)
  - `:include_measurements` - Attach measurements to metadata (default: true)
  - `:filters` - Sample filters (status, pipeline_id, date range)
  """
  def export_to_anvil(run_id, opts) do
    queue_name = Keyword.fetch!(opts, :queue_name)
    include_measurements = Keyword.get(opts, :include_measurements, true)
    filters = Keyword.get(opts, :filters, [])

    samples = ForgeStorage.get_samples_by_run(run_id, filters)

    Enum.each(samples, fn sample ->
      dto = sample_to_anvil_dto(sample, include_measurements)
      AnvilQueue.enqueue(queue_name, dto)
    end)

    {:ok, length(samples)}
  end

  @doc """
  Convert Forge sample to Anvil labeling job DTO.
  """
  def sample_to_anvil_dto(sample, include_measurements \\ true) do
    measurements = if include_measurements do
      ForgeStorage.get_measurements(sample.id)
      |> Enum.map(fn m -> {m.measurement_key, m.value} end)
      |> Map.new()
    else
      %{}
    end

    %{
      sample_id: sample.id,
      title: extract_title(sample),
      body: extract_body(sample),
      metadata: %{
        pipeline_id: sample.pipeline_id,
        created_at: sample.created_at,
        measurements: measurements,
        source_data: sample.data  # preserve raw data
      }
    }
  end

  defp extract_title(sample) do
    # Domain-specific title extraction
    cond do
      sample.data["title"] -> sample.data["title"]
      sample.data["claim"] -> "Claim: #{String.slice(sample.data["claim"], 0..50)}..."
      true -> "Sample #{String.slice(sample.id, 0..8)}"
    end
  end

  defp extract_body(sample) do
    # Primary content for labeling UI
    sample.data["text"] || sample.data["narrative"] || Jason.encode!(sample.data)
  end

  @doc """
  Sync Anvil labels back to Forge samples (enrich with annotations).
  """
  def sync_labels_to_forge(labeling_job_id) do
    # Fetch annotations from Anvil
    annotations = Anvil.Repo.all(
      from a in Anvil.Annotation,
        where: a.labeling_job_id == ^labeling_job_id,
        select: %{label: a.label, annotator_id: a.annotator_id, confidence: a.confidence}
    )

    # Resolve sample ID
    labeling_job = Anvil.Repo.get!(Anvil.LabelingJob, labeling_job_id)
    sample_id = labeling_job.sample_id

    # Store labels in Forge metadata table
    Enum.each(annotations, fn annotation ->
      ForgeStorage.insert_metadata(%{
        sample_id: sample_id,
        key: "anvil_label",
        value: annotation.label,
        value_type: "string"
      })

      ForgeStorage.insert_metadata(%{
        sample_id: sample_id,
        key: "anvil_confidence",
        value: to_string(annotation.confidence),
        value_type: "float"
      })
    end)

    {:ok, length(annotations)}
  end

  @doc """
  Resolve Forge sample by UUID (for Anvil UI queries).
  """
  def get_sample(sample_id) do
    case ForgeStorage.get_sample(sample_id) do
      {:ok, sample} -> {:ok, sample}
      {:error, :not_found} -> {:error, :sample_not_found}
    end
  end

  @doc """
  Get measurements for a sample (for Anvil UI display).
  """
  def get_measurements(sample_id) do
    ForgeStorage.get_measurements(sample_id)
  end
end
```

### 3. Anvil-Ready DTO Schema

Standardized format for labeling jobs:

```elixir
defmodule ForgeBridge.AnvilDTO do
  @type t :: %__MODULE__{
    sample_id: String.t(),
    title: String.t(),
    body: String.t(),
    metadata: map()
  }

  defstruct [
    :sample_id,    # UUID reference to forge.samples(id)
    :title,        # Short summary (displayed in queue list)
    :body,         # Main content (displayed in labeling UI)
    :metadata      # Additional context (measurements, pipeline info)
  ]
end

# Example DTO
%ForgeBridge.AnvilDTO{
  sample_id: "550e8400-e29b-41d4-a716-446655440000",
  title: "Claim: The Earth orbits the Sun",
  body: """
  Narrative 1: The Earth revolves around the Sun in an elliptical orbit...
  Narrative 2: The Sun is the center of our solar system...
  """,
  metadata: %{
    pipeline_id: "abc-123",
    created_at: ~U[2025-12-01 10:00:00Z],
    measurements: %{
      "embedding:sha256:xyz" => %{vector: [0.1, 0.2, ...], model: "text-embedding-3-small"},
      "text_length" => %{chars: 1234, words: 200}
    },
    source_data: %{
      "narrative_1" => "...",
      "narrative_2" => "...",
      "claim" => "The Earth orbits the Sun"
    }
  }
}
```

### 4. Incremental Export Workflow

Stream new samples to Anvil as they're created:

```elixir
defmodule Forge.Hooks.AnvilExporter do
  @moduledoc """
  Post-pipeline hook to auto-export samples to Anvil queue.
  """

  def after_sample_created(sample, opts) do
    if opts[:export_to_anvil] do
      queue_name = opts[:anvil_queue] || "default"

      dto = ForgeBridge.sample_to_anvil_dto(sample)
      Anvil.Queue.enqueue(queue_name, dto)

      Logger.info("Exported sample #{sample.id} to Anvil queue '#{queue_name}'")
    end
  end
end

# Enable in pipeline config
pipeline = Forge.Pipeline.new(
  source,
  stages,
  hooks: [
    {:after_sample_created, {Forge.Hooks.AnvilExporter, :after_sample_created}}
  ],
  export_to_anvil: true,
  anvil_queue: "cns_narratives"
)
```

**Alternative: Event-driven** (via PubSub):

```elixir
# Forge emits event on sample creation
Phoenix.PubSub.broadcast(
  Forge.PubSub,
  "forge:samples",
  {:sample_created, sample_id}
)

# Anvil subscribes
defmodule Anvil.ForgeSubscriber do
  use GenServer

  def init(_) do
    Phoenix.PubSub.subscribe(Forge.PubSub, "forge:samples")
    {:ok, %{}}
  end

  def handle_info({:sample_created, sample_id}, state) do
    # Fetch sample via ForgeBridge
    {:ok, sample} = ForgeBridge.get_sample(sample_id)

    # Enqueue for labeling
    dto = ForgeBridge.sample_to_anvil_dto(sample)
    Anvil.Queue.enqueue("default", dto)

    {:noreply, state}
  end
end
```

### 5. Measurement Display in Anvil UI

Anvil UI queries Forge measurements for context:

```elixir
# In Anvil LiveView
defmodule AnvilWeb.LabelingLive do
  use AnvilWeb, :live_view

  def mount(%{"job_id" => job_id}, _session, socket) do
    job = Anvil.Repo.get!(LabelingJob, job_id)

    # Fetch measurements from Forge
    measurements = ForgeBridge.get_measurements(job.sample_id)

    socket = assign(socket,
      job: job,
      measurements: measurements
    )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h2><%= @job.title %></h2>
      <div><%= @job.body %></div>

      <!-- Display measurements -->
      <div class="measurements">
        <h3>Sample Metrics</h3>
        <%= for measurement <- @measurements do %>
          <div>
            <strong><%= measurement.measurement_key %>:</strong>
            <%= format_measurement(measurement.value) %>
          </div>
        <% end %>
      </div>

      <!-- Labeling interface -->
      <.form for={@form} phx-submit="submit_label">
        <!-- ... label inputs ... -->
      </.form>
    </div>
    """
  end

  defp format_measurement(%{"vector" => vec}), do: "Vector (#{length(vec)} dims)"
  defp format_measurement(%{"chars" => chars}), do: "#{chars} characters"
  defp format_measurement(value), do: inspect(value)
end
```

### 6. Bidirectional Label Sync

After labeling, sync annotations back to Forge:

```elixir
# Anvil creates annotation
defmodule Anvil.LabelingController do
  def create_annotation(conn, %{"label" => label, "job_id" => job_id}) do
    annotation = %Annotation{
      labeling_job_id: job_id,
      label: label,
      annotator_id: conn.assigns.current_user.id,
      confidence: 1.0
    }

    Anvil.Repo.insert!(annotation)

    # Sync to Forge
    Task.start(fn ->
      ForgeBridge.sync_labels_to_forge(job_id)
    end)

    json(conn, %{status: "ok"})
  end
end

# Query labeled samples in Forge
defmodule Forge.Query do
  def get_labeled_samples(pipeline_id) do
    Forge.Repo.all(
      from s in Sample,
        join: m in Metadata, on: m.sample_id == s.id,
        where: s.pipeline_id == ^pipeline_id and m.key == "anvil_label",
        select: %{sample: s, label: m.value}
    )
  end
end
```

### 7. Export Labeled Dataset for Training

Export Forge samples + Anvil labels for model training:

```elixir
defmodule ForgeBridge.Exporter do
  @doc """
  Export labeled dataset in training-ready format.
  Returns JSONL stream: {text, label, metadata}
  """
  def export_labeled_dataset(pipeline_id, output_path) do
    labeled_samples = Forge.Query.get_labeled_samples(pipeline_id)

    File.open!(output_path, [:write], fn file ->
      Enum.each(labeled_samples, fn %{sample: sample, label: label} ->
        record = %{
          text: sample.data["text"],
          label: label,
          sample_id: sample.id,
          pipeline_id: sample.pipeline_id
        }

        IO.write(file, Jason.encode!(record) <> "\n")
      end)
    end)

    {:ok, length(labeled_samples)}
  end
end

# Usage
ForgeBridge.Exporter.export_labeled_dataset(
  "pipeline-abc-123",
  "/tmp/labeled_dataset.jsonl"
)

# Output format (JSONL)
# {"text":"The Earth orbits...","label":"entailment","sample_id":"550e8400...","pipeline_id":"abc-123"}
# {"text":"Water is wet...","label":"neutral","sample_id":"7f8e9a1b...","pipeline_id":"abc-123"}
```

### 8. Shared Configuration

Single config for both systems:

```elixir
# config/runtime.exs (shared by Forge + Anvil)
config :forge, Forge.Repo,
  username: System.get_env("POSTGRES_USER"),
  password: System.get_env("POSTGRES_PASSWORD"),
  hostname: System.get_env("POSTGRES_HOST"),
  database: System.get_env("POSTGRES_DB"),
  schema: "forge",  # Forge schema
  pool_size: 10

config :anvil, Anvil.Repo,
  username: System.get_env("POSTGRES_USER"),
  password: System.get_env("POSTGRES_PASSWORD"),
  hostname: System.get_env("POSTGRES_HOST"),
  database: System.get_env("POSTGRES_DB"),
  schema: "anvil",  # Anvil schema
  pool_size: 20

# ForgeBridge config
config :forge_bridge,
  default_queue: "default",
  include_measurements: true,
  auto_export: false  # opt-in per pipeline
```

### 9. Deployment Architecture

```
┌─────────────────────────────────────────────┐
│              Postgres (RDS)                 │
│  ┌─────────────┐      ┌─────────────┐      │
│  │ forge schema│      │anvil schema │      │
│  │  - samples  │◄─────┤ labeling_   │      │
│  │  - pipelines│  FK  │   jobs      │      │
│  │  - measure- │      │ - annotations│     │
│  │    ments    │      │              │      │
│  └─────────────┘      └─────────────┘      │
└─────────────────────────────────────────────┘
          ▲                      ▲
          │                      │
  ┌───────┴────────┐    ┌────────┴────────┐
  │  Forge Service │    │  Anvil Service  │
  │  (BEAM app)    │◄───┤  (Phoenix app)  │
  │                │    │                 │
  │  - Runner      │    │  - LiveView UI  │
  │  - Storage     │    │  - Queues       │
  │  - Telemetry   │    │  - Annotations  │
  └────────────────┘    └─────────────────┘
          ▲                      ▲
          │                      │
          └──────────────────────┘
               ForgeBridge
          (shared Elixir module)
```

## Consequences

### Positive

- **Referential integrity**: FK constraint ensures Anvil jobs always reference valid Forge samples
- **Cost savings**: Shared Postgres cluster saves $3k/year vs separate instances
- **Data consistency**: Single source of truth for samples; labels flow back to enrich Forge metadata
- **Developer ergonomics**: ForgeBridge provides clean API; no raw SQL in application code
- **Incremental sync**: Samples stream to Anvil as created (not batch uploads)
- **Measurement context**: Annotators see quality metrics during labeling (informed decisions)

### Negative

- **Coupling**: Forge and Anvil share infrastructure (blast radius; Postgres downtime affects both)
- **Schema migration coordination**: Both systems must coordinate schema changes
- **Cross-repo dependency**: ForgeBridge must be maintained in sync (breaking changes require coordination)
- **FK overhead**: ON DELETE CASCADE can slow bulk deletes (mitigate with soft deletes)

### Neutral

- **Async label sync**: Labels sync asynchronously (eventual consistency); not real-time (acceptable for batch training)
- **DTO overhead**: Conversion adds latency (~1ms per sample); negligible for human-in-the-loop workflows
- **Measurement caching**: Anvil could cache measurements in `labeling_jobs.metadata` JSONB (tradeoff: staleness vs performance)

### Alternatives Considered

1. **Separate Postgres instances**:
   - Pro: Isolation, independent scaling
   - Con: 2x cost, no FK enforcement, manual sync complexity
   - Rejected: Shared cluster benefits outweigh isolation

2. **REST API integration** (Forge HTTP API):
   - Pro: Language-agnostic, looser coupling
   - Con: Network latency, serialization overhead, no FK constraints
   - Rejected: Shared DB more performant, type-safe

3. **Message queue** (RabbitMQ/Kafka):
   - Pro: Decoupled, async, scalable
   - Con: Adds infrastructure, eventual consistency, no FK guarantees
   - Rejected: Overkill for <10k samples/day; prefer simpler shared DB

4. **CSV export/import**:
   - Pro: Simple, no code changes
   - Con: Manual, error-prone, no incremental sync, no FK relationships
   - Rejected: Not suitable for production ML workflows

5. **Anvil embeds Forge** (single monorepo):
   - Pro: Tightest coupling, single deployment
   - Con: Loss of modularity, Anvil inherits all Forge dependencies
   - Rejected: Prefer separate services with clean bridge layer

### Security Considerations

**Cross-schema access control**:
```sql
-- Forge service uses `forge_user`
CREATE USER forge_user WITH PASSWORD 'secure_password';
GRANT USAGE ON SCHEMA forge TO forge_user;
GRANT ALL ON ALL TABLES IN SCHEMA forge TO forge_user;

-- Anvil service uses `anvil_user`
CREATE USER anvil_user WITH PASSWORD 'secure_password';
GRANT USAGE ON SCHEMA anvil TO anvil_user;
GRANT ALL ON ALL TABLES IN SCHEMA anvil TO anvil_user;

-- Anvil needs read access to forge.samples for FK resolution
GRANT SELECT ON forge.samples TO anvil_user;
```

**ForgeBridge authentication**:
- Runs in Anvil process (has `anvil_user` credentials)
- Queries Forge tables via Ecto (respects DB permissions)
- No API keys required (same Postgres cluster)

### Testing Strategy

Mock ForgeBridge in Anvil tests:

```elixir
defmodule ForgeBridgeMock do
  def get_sample(sample_id) do
    {:ok, %{
      id: sample_id,
      data: %{"text" => "Mock sample"}
    }}
  end

  def get_measurements(_sample_id), do: []
end

# In test config
config :anvil, :forge_bridge, ForgeBridgeMock
```

Integration test (requires shared DB):

```elixir
defmodule ForgeBridge.IntegrationTest do
  use ExUnit.Case

  setup do
    # Create Forge sample
    sample = %Forge.Sample{
      id: UUID.uuid4(),
      pipeline_id: UUID.uuid4(),
      data: %{"text" => "Test narrative"}
    }
    Forge.Repo.insert!(sample)

    %{sample: sample}
  end

  test "exports sample to Anvil", %{sample: sample} do
    dto = ForgeBridge.sample_to_anvil_dto(sample)

    assert dto.sample_id == sample.id
    assert dto.body == "Test narrative"
  end

  test "syncs labels back to Forge", %{sample: sample} do
    # Create Anvil labeling job
    job = %Anvil.LabelingJob{
      id: UUID.uuid4(),
      sample_id: sample.id,
      title: "Test",
      body: "Test"
    }
    Anvil.Repo.insert!(job)

    # Create annotation
    annotation = %Anvil.Annotation{
      labeling_job_id: job.id,
      label: "entailment"
    }
    Anvil.Repo.insert!(annotation)

    # Sync to Forge
    {:ok, count} = ForgeBridge.sync_labels_to_forge(job.id)

    assert count == 1

    # Verify metadata in Forge
    metadata = Forge.Repo.get_by!(Forge.Metadata,
      sample_id: sample.id,
      key: "anvil_label"
    )

    assert metadata.value == "entailment"
  end
end
```
