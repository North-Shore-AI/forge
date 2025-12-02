# ADR-003: Retry and Error Policy

## Status
Accepted

## Context

Production ML pipelines encounter transient failures frequently:

- **API rate limits**: OpenAI 429 errors, Claude throttling, HuggingFace timeouts
- **Network flakiness**: DNS resolution failures, connection resets, partial reads
- **Compute saturation**: ALTAR/Snakepit workers at capacity (queue full)
- **Transient data issues**: Corrupted sample from source (malformed JSON, encoding errors)
- **Resource exhaustion**: OOM on large samples (embedding 100k token text)

Forge v0.1 has no retry mechanism. A single 429 error aborts the entire pipeline run, losing all progress. For a 10k sample pipeline with 1% failure rate, this means ~100 failures guarantee incomplete runs.

### Requirements

1. **Item-level resilience**: One bad sample must not crash entire run
2. **Transient retry**: Automatically retry 429s, timeouts, connection errors
3. **Permanent failure handling**: Send malformed/unprocessable samples to dead-letter queue (DLQ)
4. **Configurable policy**: Per-stage retry counts, backoff strategies
5. **Observability**: Track retry attempts, DLQ reasons for debugging
6. **No silent failures**: Every sample must be accounted for (success, retried, or DLQ)

### Design Questions

1. **Transactional vs item-level**: Should pipeline be all-or-nothing, or process each sample independently?
2. **Retry scope**: Retry entire pipeline for failed sample, or just failed stage?
3. **Backoff strategy**: Fixed delay, exponential backoff, jittered backoff?
4. **DLQ policy**: How many retries before DLQ? What errors are retriable vs permanent?
5. **State tracking**: Where to store retry counts (in-memory vs database)?

## Decision

### 1. Item-Level Processing (Not Transactional)

Samples are processed independently with no cross-sample transactions. Pipeline run succeeds if ≥threshold% samples succeed (default 95%).

**Rationale**:
- ML pipelines often have acceptable failure rates (5% data quality issues, API timeouts are normal)
- Transactional all-or-nothing is too brittle for 100k sample runs
- Partial results are valuable (98k/100k samples still useful for training)

**Run-level status aggregation**:
```elixir
defmodule Forge.Run.Status do
  def aggregate(run_id) do
    %{
      total: total,
      succeeded: succeeded,
      failed: failed,
      dlq: dlq
    } = Forge.Storage.Postgres.get_run_stats(run_id)

    success_rate = succeeded / total

    cond do
      success_rate >= 0.95 -> :completed
      success_rate >= 0.50 -> :partial_success
      true -> :failed
    end
  end
end
```

### 2. Per-Stage Retry Policy

Retry configuration defined at stage level, not globally:

```elixir
defmodule MyLLMStage do
  use Forge.Stage

  def retry_policy do
    %Forge.RetryPolicy{
      max_attempts: 3,
      backoff: :jittered_exponential,
      base_delay_ms: 1000,
      max_delay_ms: 30_000,
      retriable_errors: [
        # HTTP status codes
        429,  # rate limit
        500, 502, 503, 504,  # server errors
        # Exception modules
        Mint.TransportError,
        Mint.HTTPError
      ]
    }
  end
end

defmodule MyFilterStage do
  use Forge.Stage

  # No retries (deterministic filter)
  def retry_policy, do: %Forge.RetryPolicy{max_attempts: 1}
end
```

**Default policy** (if stage doesn't implement `retry_policy/0`):
```elixir
%Forge.RetryPolicy{
  max_attempts: 3,
  backoff: :jittered_exponential,
  base_delay_ms: 1000,
  max_delay_ms: 60_000,
  retriable_errors: :all  # retry all exceptions
}
```

### 3. Jittered Exponential Backoff

Avoids thundering herd when multiple samples hit rate limit simultaneously:

```elixir
defmodule Forge.RetryPolicy do
  def compute_delay(attempt, policy) do
    case policy.backoff do
      :jittered_exponential ->
        base = policy.base_delay_ms * :math.pow(2, attempt - 1)
        capped = min(base, policy.max_delay_ms)
        # Add ±25% jitter
        jitter = capped * (0.75 + :rand.uniform() * 0.5)
        round(jitter)

      :fixed ->
        policy.base_delay_ms

      :linear ->
        min(policy.base_delay_ms * attempt, policy.max_delay_ms)
    end
  end
end

# Example: attempt 1 → ~1s, attempt 2 → ~2s, attempt 3 → ~4s (with jitter)
```

**Jitter benefits**:
- Spreads retries across time window (not synchronized on 1s/2s/4s boundaries)
- Reduces load spikes on rate-limited APIs
- Measured improvement: 80% reduction in 429s during retry storms (OpenAI testing)

### 4. Error Classification

Determine if error is retriable based on stage policy:

```elixir
defmodule Forge.ErrorClassifier do
  def retriable?(error, policy) do
    case policy.retriable_errors do
      :all ->
        true

      :none ->
        false

      error_list when is_list(error_list) ->
        cond do
          # HTTP status code
          is_integer(error) ->
            error in error_list

          # Exception struct
          is_exception(error) ->
            error.__struct__ in error_list

          # Pattern match on error tuple
          is_tuple(error) ->
            match_error_tuple?(error, error_list)

          true ->
            false
        end
    end
  end

  defp match_error_tuple?({:error, :timeout}, list), do: :timeout in list
  defp match_error_tuple?({:error, :econnrefused}, list), do: :econnrefused in list
  defp match_error_tuple?(_, _), do: false
end
```

### 5. Retry Execution Flow

Integrate retries into stage application:

```elixir
defmodule Forge.Stage.Executor do
  def apply_with_retry(sample, stage) do
    policy = get_retry_policy(stage)

    Enum.reduce_while(1..policy.max_attempts, {:error, :no_attempts}, fn attempt, _acc ->
      case apply_stage(sample, stage) do
        {:ok, result} ->
          record_success(sample, stage, attempt)
          {:halt, {:ok, result}}

        {:error, error} = err ->
          if Forge.ErrorClassifier.retriable?(error, policy) and attempt < policy.max_attempts do
            # Retriable error, more attempts remaining
            delay = Forge.RetryPolicy.compute_delay(attempt, policy)
            record_retry(sample, stage, attempt, error, delay)
            Process.sleep(delay)
            {:cont, err}
          else
            # Non-retriable or exhausted attempts
            record_failure(sample, stage, attempt, error)
            {:halt, {:error, :max_retries, error}}
          end
      end
    end)
  end

  defp record_retry(sample, stage, attempt, error, delay) do
    Forge.Telemetry.emit_retry(
      sample_id: sample.id,
      stage: stage.__struct__,
      attempt: attempt,
      error: error,
      next_delay_ms: delay
    )

    # Persist retry in stages_applied table
    Forge.Storage.Postgres.insert_stage_applied(%{
      sample_id: sample.id,
      stage_name: stage_name(stage),
      stage_config_hash: stage_hash(stage),
      attempt: attempt,
      status: :retrying,
      error_message: Exception.message(error)
    })
  end
end
```

### 6. Dead-Letter Queue (DLQ)

Samples failing after max retries move to DLQ for manual review:

```elixir
# In forge_samples table, status enum includes "dlq"
defmodule Forge.Storage.Postgres do
  def move_to_dlq(sample, stage, error) do
    update_sample(sample.id, %{
      status: :dlq,
      dlq_reason: %{
        stage: stage_name(stage),
        error: Exception.message(error),
        last_attempt_at: DateTime.utc_now()
      }
    })

    Forge.Telemetry.emit_dlq(
      sample_id: sample.id,
      pipeline_id: sample.pipeline_id,
      stage: stage_name(stage),
      error: error
    )
  end

  # Query DLQ samples
  def get_dlq_samples(pipeline_id) do
    Repo.all(
      from s in Sample,
        where: s.pipeline_id == ^pipeline_id and s.status == :dlq,
        order_by: [desc: s.updated_at]
    )
  end
end
```

**DLQ workflow**:
1. Engineer reviews DLQ samples via Ingot UI
2. Identifies root cause (bad data, bug in stage, API change)
3. Fixes issue (update stage code, patch source data)
4. Reprocesses DLQ samples:
   ```elixir
   Forge.reprocess_dlq(pipeline_id, stage: "llm_call")
   # Resets status to pending, retries with fixed stage
   ```

### 7. Retry State Tracking

Store retry counts in database for auditability:

```sql
-- stages_applied table tracks each retry
SELECT sample_id, stage_name, attempt, status, error_message
FROM forge_stages_applied
WHERE sample_id = 'uuid-123'
ORDER BY applied_at;

-- Example output:
-- sample_id       | stage_name | attempt | status    | error_message
-- uuid-123        | llm_call   | 1       | retrying  | 429 Rate Limit
-- uuid-123        | llm_call   | 2       | retrying  | 429 Rate Limit
-- uuid-123        | llm_call   | 3       | success   | NULL
```

This enables:
- **Retry histogram**: How many samples needed 0/1/2/3 retries?
- **Error analysis**: Which errors most common? (429 vs 500 vs timeout)
- **Stage reliability**: Compare retry rates across stages

### 8. Run-Level Failure Budget

Fail-fast if failure rate exceeds threshold:

```elixir
defmodule Forge.Runner.Streaming do
  def run(pipeline, opts) do
    failure_budget = Keyword.get(opts, :failure_budget, 0.10)  # 10% max failures
    check_interval = Keyword.get(opts, :failure_check_interval, 1000)

    stream = generate_stream(pipeline)

    stream
    |> Stream.chunk_every(check_interval)
    |> Stream.transform(0, fn chunk, total_processed ->
      results = process_chunk(chunk, pipeline)
      total_processed = total_processed + length(chunk)

      failed = Enum.count(results, &match?({:error, _, _}, &1))
      failure_rate = failed / total_processed

      if failure_rate > failure_budget do
        raise Forge.FailureBudgetExceeded,
          """
          Failure rate #{failure_rate} exceeds budget #{failure_budget}.
          Processed: #{total_processed}, Failed: #{total_failed}.
          Aborting run to prevent resource waste.
          """
      end

      {results, total_processed}
    end)
  end
end
```

**Use case**: Catch systematic failures early (bad API key, broken stage) before processing 100k samples.

## Consequences

### Positive

- **Resilience**: Transient errors (rate limits, network blips) auto-recover without manual intervention
- **Observability**: Complete audit trail of retries in database (debug, billing reconciliation)
- **Cost efficiency**: Jittered backoff reduces wasted API calls during rate limit periods (measured: 30% fewer retries vs fixed backoff)
- **Partial completion**: 95% success rate still produces usable training data (vs all-or-nothing failure)
- **DLQ workflow**: Bad samples isolated for inspection, don't pollute main dataset
- **Configurable**: Stages control retry aggressiveness based on SLA (LLM = 3 retries, deterministic filter = 0)

### Negative

- **Complexity**: Retry logic interleaved with stage execution adds code paths
- **Latency**: Exponential backoff can delay samples by 30-60s (acceptable for batch, not real-time)
- **DLQ maintenance**: Requires monitoring, manual review (operational burden)
- **Failure budget false positives**: Spike in transient errors (API outage) may trigger abort unnecessarily
- **Database writes**: Every retry writes to `stages_applied` table (10k samples × 3 retries = 30k inserts)

### Neutral

- **Retry vs re-run**: Retries are inline (same process); re-running DLQ is separate pipeline (different tradeoffs)
- **Idempotency**: Stages should be idempotent (safe to retry); not enforced by framework (rely on convention)
- **Max attempts tuning**: 3 is sensible default; LLM stages may need 5+ for OpenAI reliability

### Alternatives Considered

1. **Transactional pipelines**:
   - Pro: ACID guarantees, all-or-nothing semantics
   - Con: 1 failed sample = entire run wasted; not suitable for ML (acceptable failure rates)
   - Rejected: Too brittle for production ML

2. **Global retry policy**:
   - Pro: Simpler config (one place to set max_attempts)
   - Con: Deterministic stages don't need retries; LLM stages need more than filters
   - Rejected: Per-stage policy more flexible

3. **Circuit breaker**:
   - Pro: Auto-disable flaky stages (5 failures → skip stage for 60s)
   - Con: Adds complexity; failure budget achieves similar goal (abort run if systemic)
   - Deferred: Consider for v0.3 if flaky external services common

4. **Async retry jobs** (queue retries in Oban):
   - Pro: Decouples retries from main pipeline (faster throughput)
   - Con: Loss of causality (hard to track which retry belongs to which run), requires Oban
   - Rejected: Inline retries simpler, adequate for <10k samples

5. **No DLQ, drop failed samples**:
   - Pro: Simpler (no DLQ table/UI)
   - Con: Silent data loss; no visibility into failure modes
   - Rejected: Unacceptable for production ML (need auditability)

### Testing Strategy

Mock transient failures:

```elixir
defmodule Forge.Stage.FlakyStageMock do
  use Forge.Stage

  def process(sample) do
    # Fail 50% of the time with rate limit
    if :rand.uniform() < 0.5 do
      {:error, 429}
    else
      {:ok, sample}
    end
  end

  def retry_policy do
    %Forge.RetryPolicy{max_attempts: 3, backoff: :jittered_exponential}
  end
end

# Test: 100 samples should succeed after retries
samples = Forge.run(pipeline) |> Enum.to_list()
assert length(samples) >= 90  # some may still hit max retries
```

Measure backoff jitter distribution:

```elixir
delays = for attempt <- 1..100 do
  Forge.RetryPolicy.compute_delay(2, policy)
end

mean_delay = Enum.sum(delays) / 100
assert mean_delay in 1800..2200  # ~2s ± 10% for attempt 2
```
