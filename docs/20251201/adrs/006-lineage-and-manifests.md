# ADR-006: Lineage and Manifests

## Status
Accepted

## Context

ML experiments require **reproducibility**: the ability to recreate a dataset or training run from historical configuration. Forge pipelines generate samples, but without lineage tracking, critical questions remain unanswered:

- **What code generated this sample?** (git SHA, library versions)
- **What configuration was used?** (source params, stage configs, measurement settings)
- **Can I reproduce this dataset?** (config + code → identical outputs)
- **Did anything change?** (detect config drift between runs)
- **Where did this sample come from?** (sample versioning, parent relationships)
- **How were secrets handled?** (audit compliance without exposing credentials)

**Current limitations**:
- v0.1 has no manifest generation
- No config versioning (can't detect pipeline changes)
- No git SHA tracking (can't tie samples to code version)
- No sample versioning (reprocessing loses provenance)
- No secrets audit trail (insecure for regulated ML)

**Regulatory/compliance drivers**:
- **GDPR Article 22**: Right to explanation (requires provenance for algorithmic decisions)
- **FDA 21 CFR Part 11**: Audit trails for ML in medical devices
- **SOC 2**: Configuration management and change tracking
- **Model Cards**: Lineage metadata for responsible AI documentation

### Requirements

1. **Pipeline manifests**: Capture complete pipeline definition (source, stages, measurements, git SHA)
2. **Config hashing**: Deterministic hashing for drift detection
3. **Sample versioning**: Track reprocessed samples with parent links
4. **Secrets handling**: Audit secret usage without storing plaintext
5. **Export formats**: Machine-readable manifests for Crucible/LineageIR integration
6. **Immutability**: Manifests are append-only (no retroactive edits)

## Decision

### 1. Pipeline Manifest Schema

Store comprehensive pipeline definition in `pipelines.manifest` JSONB field:

```elixir
defmodule Forge.Manifest do
  defstruct [
    :manifest_version,   # Schema version (currently "1.0")
    :created_at,         # UTC timestamp
    :git_sha,            # Commit hash of Forge code
    :git_branch,         # Branch name
    :git_dirty,          # Uncommitted changes present?
    :elixir_version,     # OTP/Elixir versions
    :dependencies,       # Library versions (Jason, Nx, etc.)
    :source,             # Source module + config
    :stages,             # Stage modules + configs
    :measurements,       # Measurement modules + configs
    :secrets,            # Secret references (not values!)
    :options             # Runner options (concurrency, retry policy)
  ]
end

# Example manifest
%Forge.Manifest{
  manifest_version: "1.0",
  created_at: ~U[2025-12-01 10:30:00Z],
  git_sha: "7f8d9e0a",
  git_branch: "main",
  git_dirty: false,
  elixir_version: "1.16.0 (OTP 26)",
  dependencies: %{
    "jason" => "1.4.1",
    "nx" => "0.7.0"
  },
  source: %{
    module: "CNS.Source.SyntheticNarratives",
    config: %{dataset: "gsm8k", split: "train"},
    config_hash: "sha256:abc123..."
  },
  stages: [
    %{
      module: "CNS.Stages.ClaimExtraction",
      config: %{model: "gpt-4", max_claims: 5},
      config_hash: "sha256:def456..."
    },
    %{
      module: "CNS.Stages.QualityFilter",
      config: %{min_length: 100},
      config_hash: "sha256:ghi789..."
    }
  ],
  measurements: [
    %{
      module: "Forge.Measurements.Embedding",
      config: %{model: "text-embedding-3-small"},
      config_hash: "sha256:jkl012..."
    }
  ],
  secrets: [
    %{
      name: "openai_api_key",
      referenced_by: ["CNS.Stages.ClaimExtraction"],
      hash: "sha256:mno345..."  # hash of secret value (for rotation detection)
    }
  ],
  options: %{
    concurrency: 10,
    retry_policy: %{max_attempts: 3, backoff: :jittered_exponential}
  }
}
```

### 2. Deterministic Config Hashing

Normalize and hash configs to detect drift:

```elixir
defmodule Forge.ConfigHash do
  def compute(config) do
    # Normalize: sort maps by key, remove dynamic values
    normalized = normalize(config)

    # Serialize deterministically
    binary = :erlang.term_to_binary(normalized, [:deterministic])

    # SHA256 hash
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  defp normalize(config) when is_map(config) do
    config
    |> Enum.sort()  # consistent key order
    |> Enum.map(fn {k, v} -> {k, normalize(v)} end)
    |> Map.new()
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end

# Usage
config = %{model: "gpt-4", temperature: 0.7, max_tokens: 100}
hash = Forge.ConfigHash.compute(config)
# => "sha256:abc123def456..."
```

**Hash stability**:
- Deterministic serialization (`:deterministic` flag ensures consistent encoding)
- Map key sorting (order-independent hashing)
- Excludes runtime values (timestamps, PIDs)

**Drift detection**:
```elixir
# Run pipeline twice
run1 = Forge.async_run(pipeline)
run2 = Forge.async_run(pipeline)

# Check if configs changed
manifest1 = Forge.Storage.Postgres.get_manifest(run1.pipeline_id)
manifest2 = Forge.Storage.Postgres.get_manifest(run2.pipeline_id)

if manifest1.source.config_hash != manifest2.source.config_hash do
  Logger.warn("Source config changed between runs!")
end
```

### 3. Git SHA Extraction

Capture code version at pipeline creation:

```elixir
defmodule Forge.Git do
  def current_sha do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  def current_branch do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"]) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  end

  def dirty? do
    case System.cmd("git", ["status", "--porcelain"]) do
      {"", 0} -> false
      _ -> true
    end
  end
end

# Populate manifest
defmodule Forge.Pipeline do
  def new(source, stages, opts \\ []) do
    manifest = %Forge.Manifest{
      manifest_version: "1.0",
      created_at: DateTime.utc_now(),
      git_sha: Forge.Git.current_sha(),
      git_branch: Forge.Git.current_branch(),
      git_dirty: Forge.Git.dirty?(),
      # ... rest of manifest
    }

    if manifest.git_dirty do
      Logger.warn("Creating pipeline with uncommitted changes. Reproducibility not guaranteed.")
    end

    # Store manifest in pipelines table
    Forge.Storage.Postgres.insert_pipeline(%{
      id: UUID.uuid4(),
      name: opts[:name],
      manifest: manifest,
      manifest_hash: Forge.ConfigHash.compute(manifest)
    })
  end
end
```

### 4. Sample Versioning

Track sample lineage when reprocessing:

```elixir
# pipelines table
create table(:forge_pipelines) do
  add :id, :uuid, primary_key: true
  add :parent_pipeline_id, references(:forge_pipelines, type: :uuid)
  add :manifest, :map
  add :manifest_hash, :string
  add :version, :integer, default: 1
end

# samples table
create table(:forge_samples) do
  add :id, :uuid, primary_key: true
  add :pipeline_id, references(:forge_pipelines, type: :uuid)
  add :parent_sample_id, references(:forge_samples, type: :uuid)
  add :version, :integer, default: 1
  add :data, :map
end
```

**Reprocessing workflow**:
```elixir
defmodule Forge.Pipeline do
  def reprocess(original_pipeline_id, stage_updates) do
    original = Forge.Storage.Postgres.get_pipeline(original_pipeline_id)

    # Create new pipeline with updated stages
    new_manifest = update_manifest(original.manifest, stage_updates)
    new_pipeline = %Pipeline{
      id: UUID.uuid4(),
      parent_pipeline_id: original_pipeline_id,
      version: original.version + 1,
      manifest: new_manifest,
      manifest_hash: Forge.ConfigHash.compute(new_manifest)
    }

    # Reprocess samples (link to original)
    original_samples = Forge.Storage.Postgres.get_samples(original_pipeline_id)

    Enum.each(original_samples, fn original_sample ->
      new_sample = %Sample{
        id: UUID.uuid4(),
        pipeline_id: new_pipeline.id,
        parent_sample_id: original_sample.id,
        version: original_sample.version + 1,
        data: reprocess_sample(original_sample, stage_updates)
      }

      Forge.Storage.Postgres.insert_sample(new_sample)
    end)
  end
end
```

**Lineage queries**:
```sql
-- Find all versions of a sample
WITH RECURSIVE version_chain AS (
  SELECT id, parent_sample_id, version, pipeline_id
  FROM forge_samples WHERE id = $1
  UNION ALL
  SELECT s.id, s.parent_sample_id, s.version, s.pipeline_id
  FROM forge_samples s
  JOIN version_chain vc ON s.id = vc.parent_sample_id
)
SELECT * FROM version_chain ORDER BY version;

-- Compare manifests across versions
SELECT
  p1.id as v1_pipeline,
  p2.id as v2_pipeline,
  p1.manifest -> 'stages' as v1_stages,
  p2.manifest -> 'stages' as v2_stages
FROM forge_pipelines p1
JOIN forge_pipelines p2 ON p2.parent_pipeline_id = p1.id;
```

### 5. Secrets Handling

**Policy**: Never store secret values; reference by name, hash for audit:

```elixir
defmodule Forge.Secrets do
  def reference(secret_name) do
    # Retrieve from environment or vault
    value = System.get_env(secret_name) || fetch_from_vault(secret_name)

    if is_nil(value) do
      raise "Secret #{secret_name} not found in environment"
    end

    # Hash for audit (detect rotation)
    value_hash = :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

    # Return reference (not value!)
    %{
      name: secret_name,
      hash: "sha256:#{value_hash}"
    }
  end

  defp fetch_from_vault(name) do
    # Integration with Vault/AWS Secrets Manager
    case Vault.Client.read("secret/data/#{name}") do
      {:ok, %{"data" => %{"value" => value}}} -> value
      _ -> nil
    end
  end
end

# Stage config references secrets
defmodule CNS.Stages.ClaimExtraction do
  def config do
    %{
      model: "gpt-4",
      api_key: Forge.Secrets.reference("openai_api_key")
    }
  end
end

# Manifest includes secret reference
manifest.secrets = [
  %{
    name: "openai_api_key",
    referenced_by: ["CNS.Stages.ClaimExtraction"],
    hash: "sha256:abc123..."  # hash of current secret value
  }
]
```

**Audit workflow**:
```elixir
# Detect secret rotation
old_manifest = Forge.Storage.Postgres.get_manifest(old_pipeline_id)
new_manifest = Forge.Storage.Postgres.get_manifest(new_pipeline_id)

old_secret = Enum.find(old_manifest.secrets, & &1.name == "openai_api_key")
new_secret = Enum.find(new_manifest.secrets, & &1.name == "openai_api_key")

if old_secret.hash != new_secret.hash do
  Logger.info("Secret 'openai_api_key' rotated between runs")
end
```

**Compliance**:
- Hash changes indicate secret rotation (audit trail without exposure)
- Manifests exportable for SOC 2 audits (no plaintext secrets)
- Secret names logged (traceable), values never logged

### 6. Manifest Export Formats

#### JSON Export (for Crucible/LineageIR)

```elixir
defmodule Forge.Manifest.Exporter do
  def to_json(manifest) do
    Jason.encode!(manifest, pretty: true)
  end

  def export_to_file(pipeline_id, path) do
    manifest = Forge.Storage.Postgres.get_manifest(pipeline_id)
    json = to_json(manifest)
    File.write!(path, json)
  end
end

# Usage
Forge.Manifest.Exporter.export_to_file(
  pipeline_id,
  "/tmp/pipeline_abc123_manifest.json"
)
```

#### Crucible Dataset Registry Integration

```elixir
defmodule ForgeBridge.CrucibleExporter do
  def register_dataset(run_id) do
    run = Forge.Storage.Postgres.get_run(run_id)
    manifest = Forge.Storage.Postgres.get_manifest(run.pipeline_id)

    # Convert to Crucible dataset descriptor
    descriptor = %CrucibleDatasets.Descriptor{
      name: "forge_#{run.pipeline_id}",
      source: "Forge",
      manifest_uri: upload_manifest(manifest),
      sample_count: run.samples_processed,
      created_at: run.started_at,
      lineage: %{
        git_sha: manifest.git_sha,
        config_hash: manifest.manifest_hash
      }
    }

    CrucibleDatasets.register(descriptor)
  end
end
```

#### LineageIR Emission

```elixir
defmodule ForgeBridge.LineageIRExporter do
  def emit_run(run_id) do
    run = Forge.Storage.Postgres.get_run(run_id)
    manifest = Forge.Storage.Postgres.get_manifest(run.pipeline_id)

    lineage = %LineageIR.Run{
      system: "Forge",
      run_id: run.id,
      pipeline_hash: manifest.manifest_hash,
      git_sha: manifest.git_sha,
      started_at: run.started_at,
      completed_at: run.completed_at,
      sample_count: run.samples_processed,
      artifacts: collect_artifact_uris(run.id)
    }

    LineageIR.Client.emit(lineage)
  end
end
```

### 7. Dependency Pinning

Capture library versions for reproducibility:

```elixir
defmodule Forge.Dependencies do
  def snapshot do
    # Read mix.lock
    {:ok, lock} = File.read("mix.lock")
    lock_data = Code.eval_string(lock) |> elem(0)

    # Extract versions
    Enum.map(lock_data, fn {package, info} ->
      version = extract_version(info)
      {to_string(package), version}
    end)
    |> Map.new()
  end

  defp extract_version({:hex, _package, version, _hash, _managers, _deps, _checksum, _}), do: version
  defp extract_version(_), do: "unknown"
end

# Populate manifest
manifest.dependencies = Forge.Dependencies.snapshot()
# => %{"jason" => "1.4.1", "nx" => "0.7.0", ...}
```

### 8. Manifest Diffing

Compare manifests to identify changes:

```elixir
defmodule Forge.Manifest.Differ do
  def diff(manifest1, manifest2) do
    %{
      git_sha: diff_field(manifest1.git_sha, manifest2.git_sha),
      source: diff_config(manifest1.source, manifest2.source),
      stages: diff_stages(manifest1.stages, manifest2.stages),
      measurements: diff_list(manifest1.measurements, manifest2.measurements),
      secrets: diff_secrets(manifest1.secrets, manifest2.secrets)
    }
    |> Enum.reject(fn {_k, v} -> v == :unchanged end)
    |> Map.new()
  end

  defp diff_field(v1, v2) when v1 == v2, do: :unchanged
  defp diff_field(v1, v2), do: {:changed, v1, v2}

  defp diff_config(c1, c2) do
    if c1.config_hash == c2.config_hash do
      :unchanged
    else
      {:changed, c1.config, c2.config}
    end
  end

  defp diff_stages(s1, s2) do
    # Compare by module name + config hash
    added = Enum.reject(s2, fn s -> Enum.any?(s1, & &1.module == s.module) end)
    removed = Enum.reject(s1, fn s -> Enum.any?(s2, & &1.module == s.module) end)

    changed = Enum.filter(s1, fn s1_stage ->
      s2_stage = Enum.find(s2, & &1.module == s1_stage.module)
      s2_stage && s1_stage.config_hash != s2_stage.config_hash
    end)

    %{added: added, removed: removed, changed: changed}
  end
end

# Usage
diff = Forge.Manifest.Differ.diff(old_manifest, new_manifest)
# => %{
#   git_sha: {:changed, "7f8d9e0a", "12ab34cd"},
#   stages: %{
#     changed: [%{module: "CNS.Stages.QualityFilter", ...}]
#   }
# }
```

## Consequences

### Positive

- **Reproducibility**: Complete config + git SHA enables exact recreation of datasets
- **Drift detection**: Config hashing identifies unintended changes (catch bugs before production)
- **Audit compliance**: Secrets handling meets SOC 2, GDPR requirements
- **Lineage tracking**: Sample versioning traces data through reprocessing pipelines
- **Integration**: JSON export enables Crucible/LineageIR/Model Card workflows
- **Debugging**: Manifest diffs pinpoint root cause of dataset differences

### Negative

- **Storage overhead**: Manifests are verbose (5-10KB JSONB per pipeline)
- **Git dependency**: Requires git repo (fails in Docker without .git mount)
- **Config explosion**: Many small config changes create version sprawl
- **Secrets complexity**: Hash-based audit is indirect (can't see old secret values)
- **Performance**: Hashing large configs (MB+) adds latency (acceptable for infrequent pipeline creation)

### Neutral

- **Manifest immutability**: Manifests are append-only (can't edit historical runs); some users may expect edits
- **Version numbering**: Auto-incremented integers (not semantic versioning); simple but less expressive
- **Diff granularity**: Field-level diffs (not sub-field); changing one stage param = entire stage "changed"

### Alternatives Considered

1. **No manifests** (rely on git history):
   - Pro: Simpler (no storage/hashing)
   - Con: Config in code (not data); can't query by config, no audit trail
   - Rejected: Insufficient for compliance/reproducibility

2. **DVC (Data Version Control)**:
   - Pro: Industry standard, git-based
   - Con: Heavy dependency, requires separate repo, complex learning curve
   - Rejected: Forge is library, not CLI tool; DVC overhead too high

3. **MLflow Tracking**:
   - Pro: Rich UI, versioning, model registry
   - Con: Python-centric, adds server dependency, not BEAM-native
   - Rejected: Prefer Elixir-native solution (ForgeBridge can emit to MLflow if needed)

4. **Secrets in plaintext** (encrypted at rest):
   - Pro: Full audit trail (see old secret values)
   - Con: Encryption key management, compliance risk (GDPR right to be forgotten)
   - Rejected: Hash-based audit safer (no key management)

5. **Semantic versioning** (v1.2.3 instead of integers):
   - Pro: More expressive (major/minor/patch)
   - Con: Requires manual version bumps (error-prone)
   - Rejected: Auto-increment simpler; SemVer adds cognitive load

6. **Content-addressed manifests** (hash = ID):
   - Pro: Automatic deduplication
   - Con: No human-readable IDs, hard to reference in UI
   - Rejected: UUIDs + hash index achieves similar goals

### Testing Strategy

Mock git commands:

```elixir
defmodule Forge.GitMock do
  def current_sha, do: "test_sha_abc123"
  def current_branch, do: "test_branch"
  def dirty?, do: false
end

# In test config
config :forge, :git_module, Forge.GitMock
```

Verify config hash stability:

```elixir
test "config hash is deterministic" do
  config = %{model: "gpt-4", temperature: 0.7}

  hash1 = Forge.ConfigHash.compute(config)
  hash2 = Forge.ConfigHash.compute(config)

  assert hash1 == hash2
end

test "config hash detects changes" do
  config1 = %{model: "gpt-4", temperature: 0.7}
  config2 = %{model: "gpt-4", temperature: 0.8}

  assert Forge.ConfigHash.compute(config1) != Forge.ConfigHash.compute(config2)
end
```

Verify sample versioning:

```elixir
test "reprocessing creates versioned samples" do
  pipeline1 = Forge.Pipeline.new(source, stages)
  {:ok, run1} = Forge.async_run(pipeline1)

  # Reprocess with updated stage
  pipeline2 = Forge.Pipeline.reprocess(pipeline1.id, stage_updates)
  {:ok, run2} = Forge.async_run(pipeline2)

  samples1 = Forge.Storage.Postgres.get_samples(run1.id)
  samples2 = Forge.Storage.Postgres.get_samples(run2.id)

  # v2 samples should link to v1
  assert Enum.all?(samples2, fn s2 ->
    s2.parent_sample_id in Enum.map(samples1, & &1.id)
  end)
end
```
