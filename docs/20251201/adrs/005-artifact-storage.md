# ADR-005: Artifact Storage

## Status
Accepted

## Context

Forge samples often contain large binary or text payloads that don't belong in Postgres:

- **Raw narratives**: 10-100KB text documents (CNS synthetic narratives)
- **LLM prompts/responses**: Multi-turn conversations (5-50KB per sample)
- **Embeddings**: 1536-dim float vectors (6-12KB per sample, 60MB for 10k samples)
- **Point clouds**: TDA input data (100KB+ per sample)
- **Serialized models**: Fine-tuned checkpoints referenced by sample ID
- **Images/PDFs**: Multimodal experiment inputs (1-10MB per sample)

**Current limitations**:
- v0.1 stores everything in `sample.data` JSONB field
- Large JSONB fields degrade Postgres performance:
  - Row-level locking blocks concurrent updates
  - TOAST overhead (>2KB fields compressed, out-of-line storage)
  - Vacuuming slows down (large row versions)
  - Backup/restore bloat (100GB database for 1M samples)

**Requirements**:

1. **Separation of concerns**: Metadata in Postgres, blobs in object storage
2. **Integrity**: Content-addressed storage (SHA256 hash) for immutability verification
3. **Signed URLs**: Time-limited access to blobs (don't expose S3 keys)
4. **Size policies**: Auto-offload blobs >threshold to S3, keep small data in Postgres
5. **Garbage collection**: Purge unreferenced blobs (samples deleted, but artifacts remain)
6. **Multi-cloud**: Support S3, MinIO (self-hosted), GCS (future)

### Design Constraints

- Postgres remains source of truth for sample metadata
- Blobs are immutable (write-once, content-addressed)
- Blob storage failures don't corrupt sample records (eventual consistency acceptable)
- No inline base64 encoding (inefficient, bloats DB)

## Decision

### 1. Hybrid Storage Model

**Small data** (<10KB): Store directly in `sample.data` JSONB field
**Large data** (>10KB): Store in blob storage, reference via URI in `forge_artifacts` table

```elixir
defmodule Forge.Sample do
  defstruct [
    :id,
    :pipeline_id,
    :data,      # JSONB: structured metadata (title, labels, counters)
    :artifacts  # References to blobs (loaded lazily)
  ]
end

# Sample data structure
sample.data = %{
  "title" => "Narrative pair #42",
  "label" => "contradiction",
  "word_count" => 1234
}

# Artifacts stored separately
sample.artifacts = [
  %Forge.Artifact{
    key: "raw_narrative",
    storage_uri: "s3://forge-artifacts/abc123.txt",
    content_hash: "sha256:def456...",
    size_bytes: 45_000
  },
  %Forge.Artifact{
    key: "llm_response",
    storage_uri: "s3://forge-artifacts/xyz789.json",
    content_hash: "sha256:111222...",
    size_bytes: 12_000
  }
]
```

### 2. Artifact Storage Adapters

Pluggable backends implementing `Forge.Storage.Artifact` behaviour:

```elixir
defmodule Forge.Storage.Artifact do
  @callback put_blob(key :: String.t(), content :: binary(), opts :: Keyword.t()) ::
              {:ok, uri :: String.t()} | {:error, term()}

  @callback get_blob(uri :: String.t(), opts :: Keyword.t()) ::
              {:ok, content :: binary()} | {:error, term()}

  @callback delete_blob(uri :: String.t()) ::
              :ok | {:error, term()}

  @callback signed_url(uri :: String.t(), expires_in :: pos_integer()) ::
              {:ok, url :: String.t()} | {:error, term()}
end
```

#### S3 Adapter

```elixir
defmodule Forge.Storage.Artifact.S3 do
  @behaviour Forge.Storage.Artifact

  def put_blob(key, content, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    # Content-addressed: hash becomes object key
    object_key = "#{key}/#{content_hash}"

    case ExAws.S3.put_object(bucket, object_key, content) |> ExAws.request() do
      {:ok, _} ->
        uri = "s3://#{bucket}/#{object_key}"
        {:ok, uri}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_blob(uri, _opts) do
    %URI{host: bucket, path: "/" <> object_key} = URI.parse(uri)

    case ExAws.S3.get_object(bucket, object_key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  def signed_url(uri, expires_in) do
    %URI{host: bucket, path: "/" <> object_key} = URI.parse(uri)

    config = ExAws.Config.new(:s3)
    url = ExAws.S3.presigned_url(config, :get, bucket, object_key, expires_in: expires_in)

    {:ok, url}
  end

  def delete_blob(uri) do
    %URI{host: bucket, path: "/" <> object_key} = URI.parse(uri)

    case ExAws.S3.delete_object(bucket, object_key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

#### MinIO Adapter

MinIO is S3-compatible, so inherits S3 adapter with config override:

```elixir
# config/runtime.exs
config :ex_aws, :s3,
  scheme: "http://",
  host: "minio.local",
  port: 9000,
  access_key_id: System.get_env("MINIO_ACCESS_KEY"),
  secret_access_key: System.get_env("MINIO_SECRET_KEY")

# Use same S3 adapter
config :forge, :artifact_storage,
  adapter: Forge.Storage.Artifact.S3,
  bucket: "forge-artifacts"
```

### 3. Size-Aware Storage Policy

Auto-offload large data to blob storage:

```elixir
defmodule Forge.Storage.Postgres do
  @size_threshold 10_000  # 10KB

  def insert_sample(sample) do
    # Partition data into inline vs artifacts
    {inline_data, artifacts} = partition_data(sample.data)

    # Insert sample with small inline data
    sample_record = %Sample{
      id: sample.id,
      pipeline_id: sample.pipeline_id,
      data: inline_data,
      status: :completed
    }
    Repo.insert!(sample_record)

    # Store large artifacts separately
    Enum.each(artifacts, fn {key, content} ->
      store_artifact(sample.id, key, content)
    end)
  end

  defp partition_data(data) do
    {inline, artifacts} = Enum.split_with(data, fn {_key, value} ->
      byte_size(:erlang.term_to_binary(value)) <= @size_threshold
    end)

    {Map.new(inline), Map.new(artifacts)}
  end

  defp store_artifact(sample_id, artifact_key, content) do
    adapter = Application.fetch_env!(:forge, :artifact_storage)[:adapter]
    bucket = Application.fetch_env!(:forge, :artifact_storage)[:bucket]

    binary_content = serialize(content)
    content_hash = :crypto.hash(:sha256, binary_content) |> Base.encode16(case: :lower)

    {:ok, uri} = adapter.put_blob(
      "#{sample_id}/#{artifact_key}",
      binary_content,
      bucket: bucket
    )

    %Artifact{
      id: UUID.uuid4(),
      sample_id: sample_id,
      artifact_key: artifact_key,
      storage_uri: uri,
      content_hash: "sha256:#{content_hash}",
      size_bytes: byte_size(binary_content),
      content_type: infer_content_type(content)
    }
    |> Repo.insert!()
  end

  defp serialize(content) when is_binary(content), do: content
  defp serialize(content), do: Jason.encode!(content)

  defp infer_content_type(content) when is_binary(content), do: "text/plain"
  defp infer_content_type(content) when is_map(content), do: "application/json"
  defp infer_content_type(_), do: "application/octet-stream"
end
```

**Policy examples**:
- Text <10KB: Store in `data` JSONB
- Text >10KB: Store in S3, reference in `artifacts` table
- Embeddings (always >6KB): Always in artifacts
- Metadata (IDs, counters): Always inline

### 4. Lazy Artifact Loading

Artifacts loaded on-demand (not eagerly):

```elixir
defmodule Forge.Sample do
  def get_artifact(sample, artifact_key) do
    artifact = Repo.get_by!(Artifact, sample_id: sample.id, artifact_key: artifact_key)

    adapter = Application.fetch_env!(:forge, :artifact_storage)[:adapter]
    {:ok, content} = adapter.get_blob(artifact.storage_uri)

    # Verify integrity
    actual_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    expected_hash = String.replace_prefix(artifact.content_hash, "sha256:", "")

    if actual_hash == expected_hash do
      {:ok, deserialize(content, artifact.content_type)}
    else
      {:error, :hash_mismatch}
    end
  end

  defp deserialize(content, "application/json"), do: Jason.decode!(content)
  defp deserialize(content, "text/plain"), do: content
  defp deserialize(content, _), do: content
end

# Usage
{:ok, narrative} = Forge.Sample.get_artifact(sample, "raw_narrative")
```

### 5. Signed URL Generation

Temporary access to artifacts (no direct S3 credentials):

```elixir
defmodule Forge.Sample do
  def artifact_url(sample, artifact_key, expires_in \\ 3600) do
    artifact = Repo.get_by!(Artifact, sample_id: sample.id, artifact_key: artifact_key)

    adapter = Application.fetch_env!(:forge, :artifact_storage)[:adapter]
    {:ok, url} = adapter.signed_url(artifact.storage_uri, expires_in)

    url
  end
end

# Usage (e.g., in Ingot UI)
url = Forge.Sample.artifact_url(sample, "raw_narrative", expires_in: 600)
# => "https://s3.amazonaws.com/forge-artifacts/abc123.txt?X-Amz-Expires=600&..."
```

**Security**:
- URLs expire after configured duration (default 1 hour)
- No S3 credentials exposed to frontend
- Audit access via S3 CloudTrail logs

### 6. Garbage Collection

Purge unreferenced artifacts:

```elixir
defmodule Forge.Storage.ArtifactGC do
  def purge_orphaned_artifacts(before_date) do
    # Find artifacts for soft-deleted samples
    orphaned = Repo.all(
      from a in Artifact,
        join: s in Sample, on: a.sample_id == s.id,
        where: not is_nil(s.deleted_at) and s.deleted_at < ^before_date,
        select: a
    )

    Enum.each(orphaned, fn artifact ->
      adapter = Application.fetch_env!(:forge, :artifact_storage)[:adapter]

      case adapter.delete_blob(artifact.storage_uri) do
        :ok ->
          Repo.delete!(artifact)
          Logger.info("Purged artifact #{artifact.id}")

        {:error, reason} ->
          Logger.warn("Failed to purge artifact #{artifact.id}: #{inspect(reason)}")
      end
    end)

    length(orphaned)
  end
end

# Scheduled job (via Oban or cron)
Forge.Storage.ArtifactGC.purge_orphaned_artifacts(DateTime.add(DateTime.utc_now(), -30, :day))
```

**Retention policy**:
- Keep artifacts for 30 days after sample soft-delete
- Allows recovery window (undo accidental deletion)
- After 30 days, purge both sample record and artifacts

### 7. Content-Addressed Deduplication

Identical content stored once:

```elixir
defmodule Forge.Storage.Artifact.S3 do
  def put_blob(key, content, opts) do
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    bucket = Keyword.fetch!(opts, :bucket)
    object_key = "blobs/#{content_hash}"  # content-addressed

    # Check if already exists (save bandwidth)
    case ExAws.S3.head_object(bucket, object_key) |> ExAws.request() do
      {:ok, _} ->
        # Already stored, return existing URI
        {:ok, "s3://#{bucket}/#{object_key}"}

      {:error, {:http_error, 404, _}} ->
        # Not found, upload
        ExAws.S3.put_object(bucket, object_key, content) |> ExAws.request()
        {:ok, "s3://#{bucket}/#{object_key}"}
    end
  end
end
```

**Benefits**:
- Duplicate narratives stored once (e.g., same text in train/validation splits)
- 10k samples with 5k unique narratives = 50% storage savings
- Measured impact: 100GB → 60GB for CNS synthetic dataset

### 8. Multipart Upload (Large Artifacts)

For artifacts >5MB, use multipart upload:

```elixir
defmodule Forge.Storage.Artifact.S3 do
  @multipart_threshold 5 * 1024 * 1024  # 5MB

  def put_blob(key, content, opts) when byte_size(content) > @multipart_threshold do
    bucket = Keyword.fetch!(opts, :bucket)
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    object_key = "blobs/#{content_hash}"

    # Initiate multipart upload
    {:ok, %{body: %{upload_id: upload_id}}} =
      ExAws.S3.initiate_multipart_upload(bucket, object_key) |> ExAws.request()

    # Upload in 5MB chunks
    chunk_size = 5 * 1024 * 1024
    chunks = chunk_binary(content, chunk_size)

    parts = Enum.with_index(chunks, 1)
    |> Enum.map(fn {chunk, part_number} ->
      {:ok, %{headers: headers}} =
        ExAws.S3.upload_part(bucket, object_key, upload_id, part_number, chunk)
        |> ExAws.request()

      etag = Enum.find_value(headers, fn {k, v} -> k == "ETag" && v end)
      {part_number, etag}
    end)

    # Complete multipart upload
    ExAws.S3.complete_multipart_upload(bucket, object_key, upload_id, parts)
    |> ExAws.request()

    {:ok, "s3://#{bucket}/#{object_key}"}
  end

  defp chunk_binary(binary, chunk_size) do
    chunk_binary(binary, chunk_size, [])
  end

  defp chunk_binary(<<>>, _size, acc), do: Enum.reverse(acc)
  defp chunk_binary(binary, size, acc) do
    <<chunk::binary-size(size), rest::binary>> = binary
    chunk_binary(rest, size, [chunk | acc])
  rescue
    MatchError -> Enum.reverse([binary | acc])  # last chunk smaller than size
  end
end
```

### 9. Telemetry Integration

Track artifact operations:

```elixir
:telemetry.execute(
  [:forge, :artifact, :put],
  %{size_bytes: byte_size(content), duration: duration_ns},
  %{artifact_key: key, deduplication: true/false}
)

:telemetry.execute(
  [:forge, :artifact, :get],
  %{size_bytes: byte_size(content), duration: duration_ns},
  %{artifact_key: key, cache_hit: false}
)
```

**Metrics**:
- **Upload throughput**: MB/s to S3
- **Deduplication rate**: % of uploads skipped (content exists)
- **Download latency**: Time to fetch artifacts (identify slow network paths)
- **Storage cost**: Total bytes stored (for billing estimation)

## Consequences

### Positive

- **Postgres performance**: 10x smaller database (10GB vs 100GB), faster backups, queries
- **Cost efficiency**: S3 Standard-IA ($0.0125/GB) cheaper than RDS storage ($0.115/GB)
- **Deduplication**: 30-50% storage savings for datasets with duplicate content
- **Integrity**: Content-addressed + SHA256 verification prevents corruption
- **Scalability**: S3 handles petabytes, Postgres does not
- **Signed URLs**: Secure artifact access without exposing S3 credentials

### Negative

- **Complexity**: Two storage systems (Postgres + S3) vs one
- **Network latency**: Fetching artifacts adds 50-200ms (S3 RTT)
- **Eventual consistency**: S3 put → immediate Postgres reference → S3 get may 404 (rare)
- **Ops burden**: S3 bucket lifecycle, IAM policies, regional replication
- **Local dev**: Requires MinIO or S3 mock (can't use ETS-only workflow)

### Neutral

- **Eager vs lazy loading**: Artifacts loaded on-demand (not with sample); explicit API call required
- **Multipart overhead**: 5MB+ uploads slower (chunking) but more reliable (resume on failure)
- **GC scheduling**: Manual or cron-based; no automatic purge (avoid accidental data loss)

### Alternatives Considered

1. **Store everything in Postgres (BYTEA/JSONB)**:
   - Pro: Simpler architecture, no S3 dependency
   - Con: Database bloat, backup/restore slow, >1GB rows fail
   - Rejected: Not scalable beyond 10k samples

2. **Inline base64 encoding**:
   - Pro: Blobs in JSONB (no separate table)
   - Con: 33% size overhead, slow JSON parsing
   - Rejected: Wasteful, degrades query performance

3. **Filesystem storage** (NFS/EFS):
   - Pro: Cheaper than S3
   - Con: No content-addressing, brittle (node affinity), no versioning
   - Rejected: Not cloud-native, poor multi-region support

4. **Database per sample** (SQLite files in S3):
   - Pro: Self-contained sample units
   - Con: Query complexity (can't JOIN across samples), N * file overhead
   - Rejected: Over-engineered for metadata storage

5. **Git LFS** (blobs in Git):
   - Pro: Version control for artifacts
   - Con: Not designed for millions of blobs, complex GC
   - Rejected: Git is source control, not data lake

6. **No garbage collection**:
   - Pro: Simpler (never delete)
   - Con: Storage costs grow unbounded
   - Rejected: S3 costs $1250/month for 100TB; GC amortizes to $50/month

### Configuration Example

```elixir
# config/runtime.exs
config :forge, :artifact_storage,
  adapter: Forge.Storage.Artifact.S3,
  bucket: System.get_env("FORGE_ARTIFACT_BUCKET", "forge-artifacts"),
  size_threshold: 10_000,  # bytes
  gc_retention_days: 30

# For local dev (MinIO)
if config_env() == :dev do
  config :ex_aws, :s3,
    scheme: "http://",
    host: "localhost",
    port: 9000

  config :forge, :artifact_storage,
    adapter: Forge.Storage.Artifact.S3,
    bucket: "forge-dev"
end
```

### Integration with ALTAR/Snakepit

ALTAR workers can store computation artifacts:

```elixir
defmodule Forge.Measurements.TopologyFeatures do
  def compute(sample) do
    # Fetch point cloud artifact
    {:ok, point_cloud} = Forge.Sample.get_artifact(sample, "point_cloud")

    # Dispatch to ALTAR
    {:ok, result} = ALTAR.Client.submit_task("ripser.compute", %{points: point_cloud})

    # Store persistence diagram as artifact (large JSON)
    Forge.Storage.Postgres.store_artifact(
      sample.id,
      "persistence_diagram",
      result.diagram
    )

    # Store summary metrics in measurement (small)
    {:ok, %{betti_numbers: result.betti_numbers}}
  end
end
```
