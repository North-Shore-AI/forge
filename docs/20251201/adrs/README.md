# Forge Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Forge repository buildout (2025-12-01).

## ADR Index

### Storage & Infrastructure

- **[ADR-001: Postgres Storage Adapter](./001-postgres-storage-adapter.md)** (12KB)
  - Decision to add Postgres storage alongside ETS
  - Table design: pipelines, samples, stages_applied, measurements, artifacts, metadata
  - Indexing strategy, soft deletes, sample versioning
  - Shared cluster with Anvil (separate schemas)

- **[ADR-005: Artifact Storage](./005-artifact-storage.md)** (17KB)
  - Blob storage (S3/MinIO) for large artifacts
  - URI + hash storage in Postgres
  - Size-aware policies, content-addressed deduplication
  - Signed URL generation, garbage collection

### Execution & Reliability

- **[ADR-002: Execution Engine Design](./002-execution-engine-design.md)** (12KB)
  - Runner architecture: streaming vs batch modes
  - Backpressure via demand, async stage execution
  - Configurable concurrency
  - GenServer vs Broadway vs Oban tradeoffs

- **[ADR-003: Retry and Error Policy](./003-retry-and-error-policy.md)** (14KB)
  - Item-level processing (not transactional all-or-nothing)
  - Retry policy per stage (max attempts, jittered backoff)
  - Dead-letter queue design
  - Run-level status aggregation

### Features & Measurements

- **[ADR-004: Measurement Orchestration](./004-measurement-orchestration.md)** (15KB)
  - Post-create measurement pipelines
  - Async execution, idempotency via deterministic measurement IDs
  - ALTAR/Snakepit integration for external compute
  - Batch-capable measurements, versioning

### Lineage & Observability

- **[ADR-006: Lineage and Manifests](./006-lineage-and-manifests.md)** (19KB)
  - Pipeline manifests with source config hash, stage configs, measurement configs, git SHA
  - Sample versioning with parent_sample_id
  - Secrets handling: reference by name only, hash for audit (never store values)
  - Export formats for Crucible/LineageIR integration

- **[ADR-007: Telemetry Integration](./007-telemetry-integration.md)** (22KB)
  - :telemetry events for stage start/stop, measurement start/stop, retries, DLQ, storage writes
  - Metrics: throughput, failure rates, latency per stage, queue depth
  - OpenTelemetry/StatsD/Prometheus compatibility
  - Structured logging with trace context

### Integration

- **[ADR-008: Anvil Integration](./008-anvil-integration.md)** (20KB)
  - Samples referenceable via UUID
  - ForgeBridge for sample resolution
  - Helper to emit Anvil-ready DTOs (title/body/metadata)
  - Shared Postgres FK relationship
  - Bidirectional label sync

## Reading Order

### For Platform Engineers
1. ADR-001 (Postgres storage) - Foundation
2. ADR-002 (Execution engine) - Core runtime
3. ADR-003 (Retry/error policy) - Reliability
4. ADR-007 (Telemetry) - Observability

### For ML Engineers
1. ADR-004 (Measurements) - Feature computation
2. ADR-006 (Lineage) - Reproducibility
3. ADR-005 (Artifacts) - Large data handling
4. ADR-008 (Anvil) - Labeling integration

### For Architecture Review
Read all in numerical order (001-008) for comprehensive understanding.

## Document Format

All ADRs follow the standard format:

```markdown
# ADR-NNN: Title

## Status
Proposed | Accepted | Deprecated | Superseded

## Context
[Problem/situation requiring a decision]

## Decision
[The decision made and rationale]

## Consequences
### Positive
- ...

### Negative
- ...

### Neutral
- ...
```

## Related Documentation

- **Buildout Plan**: `/home/home/p/g/North-Shore-AI/docs/20251201/forge.md`
- **Forge Repository**: `/home/home/p/g/North-Shore-AI/ingot/forge/`
- **Integration Docs**: See ADR-008 for Anvil integration details

## Maintenance

- ADRs are immutable once accepted (capture decision at point in time)
- Superseded decisions should reference the new ADR
- New ADRs should start at 009 and increment

## Total Documentation Size

- **8 ADRs**: 131KB total
- **Average**: 16.4KB per ADR
- **Range**: 12KB (ADR-001, ADR-002) to 22KB (ADR-007)

Generated: 2025-12-01
