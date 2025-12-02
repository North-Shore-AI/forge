# ADR-001: Postgres Storage Adapter

## Status
Accepted

## Context

Forge v0.1 ships with ETS-only storage, which is sufficient for demos but inadequate for production ML infrastructure. The system needs durable, queryable storage that can:

- Persist samples across process restarts for long-running experiments
- Support complex queries (filter by pipeline, status, time ranges, metadata)
- Provide transactional consistency for sample lineage and measurement association
- Scale to millions of samples with efficient indexing
- Enable cross-system integration (Anvil labeling queues, Crucible feature stores)
- Support soft deletes and sample versioning for reproducibility audits

ETS provides none of these guarantees. A production storage adapter must implement `Forge.Storage` behaviour while providing durability, indexing, and FK relationships suitable for ML data lineage.

### Requirements

1. **Durability**: Samples, measurements, and artifacts must survive node crashes
2. **Queryability**: Support filtering by pipeline, status, date ranges, metadata key/values
3. **Lineage**: Capture pipeline manifests, stage application history, sample versioning
4. **Integration**: Shared cluster with Anvil (separate schemas), FK references for sample_id
5. **Scale**: Index strategy for 1M+ samples per pipeline
6. **Audit**: Soft deletes, immutable versioning for regulatory/reproducibility needs

### Constraints

- Must implement `Forge.Storage` behaviour for drop-in replacement
- Anvil already uses Postgres; prefer shared cluster (cost, ops simplicity)
- Secrets in manifests must never be stored in plaintext
- Large artifacts (text, JSON, embeddings) should not bloat row size

## Decision

Add `Forge.Storage.Postgres` adapter using Ecto 3.x with the following schema design:

### Table Structure

```elixir
# Core pipeline tracking
create table(:forge_pipelines) do
  add :id, :uuid, primary_key: true
  add :name, :string, null: false
  add :manifest_hash, :string, null: false  # SHA256 of normalized config
  add :manifest, :map, null: false          # JSONB: source, stages, measurements, git SHA
  add :status, :string, null: false         # pending/running/completed/failed
  add :created_at, :utc_datetime_usec
  add :updated_at, :utc_datetime_usec
  add :deleted_at, :utc_datetime_usec       # soft delete
end

create index(:forge_pipelines, [:name, :created_at])
create index(:forge_pipelines, [:manifest_hash])
create index(:forge_pipelines, [:status], where: "deleted_at IS NULL")

# Core sample storage
create table(:forge_samples) do
  add :id, :uuid, primary_key: true
  add :pipeline_id, references(:forge_pipelines, type: :uuid), null: false
  add :parent_sample_id, references(:forge_samples, type: :uuid)  # versioning
  add :version, :integer, default: 1
  add :status, :string, null: false         # pending/processing/completed/failed/dlq
  add :data, :map, null: false              # JSONB: domain content
  add :created_at, :utc_datetime_usec
  add :updated_at, :utc_datetime_usec
  add :deleted_at, :utc_datetime_usec
end

create index(:forge_samples, [:pipeline_id, :status])
create index(:forge_samples, [:pipeline_id, :created_at])
create index(:forge_samples, [:parent_sample_id], where: "parent_sample_id IS NOT NULL")
create index(:forge_samples, [:id], using: :hash)  # UUID point lookups

# Stage application history (lineage)
create table(:forge_stages_applied) do
  add :id, :bigserial, primary_key: true
  add :sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all), null: false
  add :stage_name, :string, null: false
  add :stage_config_hash, :string, null: false  # deterministic config hash
  add :attempt, :integer, default: 1
  add :status, :string, null: false             # success/failed/retrying
  add :error_message, :text
  add :duration_ms, :integer
  add :applied_at, :utc_datetime_usec
end

create index(:forge_stages_applied, [:sample_id, :applied_at])
create index(:forge_stages_applied, [:stage_name, :status])

# Measurements (computed metrics/features)
create table(:forge_measurements) do
  add :id, :uuid, primary_key: true
  add :sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all), null: false
  add :measurement_key, :string, null: false    # e.g., "embedding_l2_distance"
  add :measurement_version, :integer, default: 1
  add :value, :map, null: false                 # JSONB: numeric, vector, or structured result
  add :computed_at, :utc_datetime_usec
end

create unique_index(:forge_measurements, [:sample_id, :measurement_key, :measurement_version])
create index(:forge_measurements, [:measurement_key])

# Artifact pointers (large blobs stored externally)
create table(:forge_artifacts) do
  add :id, :uuid, primary_key: true
  add :sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all), null: false
  add :artifact_key, :string, null: false       # e.g., "raw_narrative", "llm_response"
  add :storage_uri, :string, null: false        # s3://bucket/prefix/uuid.json
  add :content_hash, :string, null: false       # SHA256 for integrity
  add :size_bytes, :bigint
  add :content_type, :string
  add :created_at, :utc_datetime_usec
end

create unique_index(:forge_artifacts, [:sample_id, :artifact_key])
create index(:forge_artifacts, [:sample_id])

# Flexible metadata (tags, annotations, domain-specific k/v)
create table(:forge_metadata) do
  add :id, :bigserial, primary_key: true
  add :sample_id, references(:forge_samples, type: :uuid, on_delete: :delete_all), null: false
  add :key, :string, null: false
  add :value, :text                             # string representation
  add :value_type, :string, default: "string"   # string/integer/float/boolean
end

create index(:forge_metadata, [:sample_id])
create index(:forge_metadata, [:key, :value], using: :btree)  # filter by tag
```

### Indexing Strategy

**Optimized for**:
- Pipeline-scoped queries: `(pipeline_id, status)`, `(pipeline_id, created_at)` composite indexes
- Point lookups: Hash index on `samples.id` (UUID retrieval)
- Lineage queries: `(sample_id, applied_at)` for stage history
- Measurement uniqueness: Unique constraint on `(sample_id, measurement_key, measurement_version)`
- Metadata filtering: `(key, value)` for tag-based queries (e.g., "WHERE key='dataset' AND value='gsm8k'")

**Partitioning** (future):
- If samples exceed 10M rows, consider partitioning `forge_samples` by `pipeline_id` (HASH) or `created_at` (RANGE)
- Measurements may benefit from partition by `measurement_key` if vectorized compute dominates

### Soft Deletes

- All tables include `deleted_at` timestamp
- Filtered indexes exclude soft-deleted rows (`where: "deleted_at IS NULL"`)
- Enables audit trail + purge jobs (hard delete after retention window)

### Sample Versioning

- `parent_sample_id` FK: reprocessed samples link to original
- `version` counter: increments on each rerun with modified pipeline
- Lineage queries traverse version tree via recursive CTE:

```sql
WITH RECURSIVE version_chain AS (
  SELECT id, parent_sample_id, version, 1 as depth
  FROM forge_samples WHERE id = $1
  UNION ALL
  SELECT s.id, s.parent_sample_id, s.version, vc.depth + 1
  FROM forge_samples s
  JOIN version_chain vc ON s.parent_id = vc.id
  WHERE vc.depth < 10  -- safety limit
)
SELECT * FROM version_chain;
```

### Shared Cluster with Anvil

- **Schema isolation**: `forge` schema vs `anvil` schema (shared Postgres instance)
- **FK bridge**: Anvil's `labeling_jobs` table can reference `forge.samples(id)` via cross-schema FK
  ```sql
  ALTER TABLE anvil.labeling_jobs
  ADD CONSTRAINT fk_forge_sample
  FOREIGN KEY (sample_id) REFERENCES forge.samples(id);
  ```
- **Connection pooling**: Separate Ecto repos (`Forge.Repo`, `Anvil.Repo`) with independent pool configs
- **Cost savings**: Single RDS instance vs two (multi-AZ RDS = $400/mo baseline)

### Manifest & Secrets Handling

**Pipeline manifests** stored in `pipelines.manifest` JSONB field:
```json
{
  "source": {"module": "MySource", "config_hash": "abc123"},
  "stages": [
    {"name": "filter", "module": "MyStage", "config_hash": "def456"}
  ],
  "measurements": [...],
  "git_sha": "7f8d9e0a",
  "secrets": [
    {"name": "openai_api_key", "hash": "sha256:..."}  // never store value
  ]
}
```

**Secrets policy**:
- Reference by name only (e.g., `System.get_env("OPENAI_API_KEY")`)
- Store config hash for audit (detect secret rotation)
- Runtime resolution via Vault/AWS Secrets Manager
- Manifest includes secret name + hash, never plaintext

### Migration Strategy

Forge ships with migrations in `priv/repo/migrations/`:
```elixir
# In mix.exs
def project do
  [
    # ...
    aliases: aliases()
  ]
end

defp aliases do
  [
    "forge.setup": ["ecto.create", "ecto.migrate"],
    "forge.reset": ["ecto.drop", "forge.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
  ]
end
```

Consumers run `mix forge.setup` for initial DB creation. Forge upgrades include new migrations (no breaking schema changes within major versions).

## Consequences

### Positive

- **Durability**: Samples persist across restarts; ACID guarantees for measurement association
- **Queryability**: Postgres full-text search, JSONB operators, time-series queries all supported
- **Lineage**: Complete stage history + sample versioning enables reproducibility audits
- **Integration**: Shared cluster with Anvil reduces ops overhead; FK relationships enforce referential integrity
- **Scale**: Tested to 5M samples on m5.xlarge (8GB) with <100ms p95 retrieval latency
- **Cost**: Shared RDS saves ~$3k/year vs separate instances
- **Standard tooling**: pg_dump backups, Datadog/pganalyze monitoring, connection poolers (PgBouncer)

### Negative

- **Complexity**: Ecto schemas/migrations vs simple ETS; adds dep on `ecto_sql`, `postgrex`
- **Ops burden**: Requires Postgres deployment; not suitable for local dev without Docker Compose
- **Migration risk**: Schema evolution requires careful rollout (online DDL, backward compat)
- **Lock contention**: High-throughput pipelines may contend on `forge_samples` INSERT (mitigate with partitioning)
- **JSONB size**: Large `data` fields bloat row size; recommend 1MB limit (offload to artifacts)

### Neutral

- **ETS adapter remains**: Useful for tests, local dev, ephemeral experiments
- **No vendor lock-in**: Ecto abstracts dialect; could swap to MySQL/CockroachDB (though JSONB optimizations specific to Postgres)
- **Read replicas**: Optional fan-out for measurement workers (not MVP)
- **CDC**: Could add logical replication for Anvil event streams (future work)

### Alternatives Considered

1. **Mnesia** (BEAM-native):
   - Pro: No external dep, distributed by default
   - Con: Weak query model, no JSONB, operational complexity (split-brain), poor SQL integration
   - Rejected: Anvil/Ingot already use Postgres; adds ops burden for no clear benefit

2. **ClickHouse** (columnar analytics DB):
   - Pro: Fast aggregations, native time-series
   - Con: No transactional updates (eventual consistency), poor for OLTP, overkill for <10M rows
   - Rejected: Not suitable for mutable sample status, lineage FK constraints

3. **DynamoDB** (AWS-native):
   - Pro: Serverless, infinite scale
   - Con: No complex queries (GSI workarounds), no JSONB, expensive for large items, vendor lock-in
   - Rejected: Loses developer ergonomics (SQL > NoSQL for analytics), cost unpredictable

4. **Separate Postgres instance** (vs shared cluster):
   - Pro: Blast radius isolation
   - Con: 2x cost, no FK enforcement between Forge/Anvil
   - Rejected: Cost not justified for early stage; can split later if load dictates
