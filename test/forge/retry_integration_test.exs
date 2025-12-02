defmodule Forge.RetryIntegrationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.{Runner, Sample, RetryPolicy}

  require Logger

  # Test stages demonstrating retry behaviors
  defmodule AttemptTracker do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def get_and_increment(sample_id) do
      Agent.get_and_update(__MODULE__, fn state ->
        current = Map.get(state, sample_id, 0)
        {current, Map.put(state, sample_id, current + 1)}
      end)
    end

    def reset do
      Agent.update(__MODULE__, fn _ -> %{} end)
    end
  end

  defmodule FlakyStage do
    @behaviour Forge.Stage

    def process(%{id: id, data: %{fail_count: fail_count}} = sample) do
      attempt = AttemptTracker.get_and_increment(id)

      if attempt < fail_count do
        {:error, 429}
      else
        # Success after retries
        updated_sample = %{
          sample
          | data: Map.put(sample.data, :processed, true)
        }

        {:ok, updated_sample}
      end
    end

    def retry_policy do
      RetryPolicy.new(
        max_attempts: 5,
        backoff: :fixed,
        base_delay_ms: 5,
        retriable_errors: [429]
      )
    end
  end

  defmodule PermanentFailStage do
    @behaviour Forge.Stage

    def process(_sample) do
      {:error, :unrecoverable}
    end

    def retry_policy do
      RetryPolicy.new(
        max_attempts: 2,
        backoff: :fixed,
        base_delay_ms: 5,
        retriable_errors: :none
      )
    end
  end

  defmodule TestPipelines do
    use Forge.Pipeline

    pipeline :flaky_with_recovery do
      source(Forge.Source.Static,
        data: [
          %{value: 1, fail_count: 2},
          %{value: 2, fail_count: 1},
          %{value: 3, fail_count: 0}
        ]
      )

      stage(Forge.RetryIntegrationTest.FlakyStage)
    end

    pipeline :permanent_failures do
      source(Forge.Source.Static,
        data: [
          %{value: 1},
          %{value: 2}
        ]
      )

      stage(Forge.RetryIntegrationTest.PermanentFailStage)
    end
  end

  describe "retry integration with Runner" do
    setup do
      # Start the attempt tracker
      {:ok, _pid} = start_supervised(AttemptTracker)
      AttemptTracker.reset()
      :ok
    end

    @tag capture_log: true
    test "successfully processes samples after transient failures" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :flaky_with_recovery
        )

      samples = Runner.run(pid)

      # All samples should succeed after retries
      assert length(samples) == 3
      assert Enum.all?(samples, &Sample.ready?/1)
      assert Enum.all?(samples, fn s -> s.data.processed == true end)

      # Check status for retry tracking
      status = Runner.status(pid)
      assert status.samples_processed == 3
      assert status.samples_skipped == 0
      assert status.samples_dlq == 0

      Runner.stop(pid)
    end

    @tag capture_log: true
    test "moves samples to DLQ after max retries with permanent failures" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :permanent_failures
        )

      samples = Runner.run(pid)

      # All samples should fail immediately (non-retriable error)
      assert length(samples) == 0

      # Check status
      status = Runner.status(pid)
      assert status.samples_processed == 0
      assert status.samples_skipped == 0
      assert status.samples_dlq == 2

      Runner.stop(pid)
    end
  end

  describe "Sample DLQ status" do
    test "marks sample with DLQ status and reason" do
      sample = Sample.new(id: "123", pipeline: :test, data: %{value: 42})

      dlq_sample =
        Sample.mark_dlq(sample, %{
          stage: "MyStage",
          error: "Rate limit exceeded",
          attempts: 3
        })

      assert dlq_sample.status == :dlq
      assert Sample.dlq?(dlq_sample)
      assert dlq_sample.dlq_reason.stage == "MyStage"
      assert dlq_sample.dlq_reason.error == "Rate limit exceeded"
      assert dlq_sample.dlq_reason.attempts == 3
      assert dlq_sample.dlq_reason.timestamp != nil
    end
  end

  describe "backoff strategies in real execution" do
    test "jittered exponential backoff shows variance in delays" do
      policy =
        RetryPolicy.new(
          backoff: :jittered_exponential,
          base_delay_ms: 100,
          max_delay_ms: 1000
        )

      # Compute delays for multiple attempts
      delays_attempt_1 = for _ <- 1..20, do: RetryPolicy.compute_delay(1, policy)
      delays_attempt_2 = for _ <- 1..20, do: RetryPolicy.compute_delay(2, policy)

      # Should have variance (jitter working)
      assert length(Enum.uniq(delays_attempt_1)) > 1
      assert length(Enum.uniq(delays_attempt_2)) > 1

      # Ranges should be correct
      # Attempt 1: 100 * 2^0 = 100, with ±25% jitter = 75-125
      assert Enum.all?(delays_attempt_1, &(&1 >= 75 and &1 <= 125))

      # Attempt 2: 100 * 2^1 = 200, with ±25% jitter = 150-250
      assert Enum.all?(delays_attempt_2, &(&1 >= 150 and &1 <= 250))
    end

    test "fixed backoff is deterministic" do
      policy = RetryPolicy.new(backoff: :fixed, base_delay_ms: 100)

      delays = for _ <- 1..10, do: RetryPolicy.compute_delay(1, policy)

      # All delays should be identical
      assert length(Enum.uniq(delays)) == 1
      assert hd(delays) == 100
    end

    test "linear backoff scales proportionally" do
      policy = RetryPolicy.new(backoff: :linear, base_delay_ms: 100)

      assert RetryPolicy.compute_delay(1, policy) == 100
      assert RetryPolicy.compute_delay(2, policy) == 200
      assert RetryPolicy.compute_delay(3, policy) == 300
      assert RetryPolicy.compute_delay(4, policy) == 400
    end
  end

  describe "error classification edge cases" do
    test "classifies mixed error types correctly" do
      policy =
        RetryPolicy.new(retriable_errors: [429, RuntimeError, :timeout, :econnrefused])

      alias Forge.ErrorClassifier

      # HTTP codes
      assert ErrorClassifier.retriable?(429, policy)
      refute ErrorClassifier.retriable?(404, policy)

      # Exceptions
      assert ErrorClassifier.retriable?(%RuntimeError{}, policy)
      refute ErrorClassifier.retriable?(%ArgumentError{}, policy)

      # Error tuples
      assert ErrorClassifier.retriable?({:error, :timeout}, policy)
      assert ErrorClassifier.retriable?({:error, :econnrefused}, policy)
      refute ErrorClassifier.retriable?({:error, :nxdomain}, policy)
    end

    test "handles :all and :none policies" do
      all_policy = RetryPolicy.new(retriable_errors: :all)
      none_policy = RetryPolicy.new(retriable_errors: :none)

      alias Forge.ErrorClassifier

      assert ErrorClassifier.retriable?(429, all_policy)
      assert ErrorClassifier.retriable?(%RuntimeError{}, all_policy)
      assert ErrorClassifier.retriable?({:error, :timeout}, all_policy)
      assert ErrorClassifier.retriable?("any error", all_policy)

      refute ErrorClassifier.retriable?(429, none_policy)
      refute ErrorClassifier.retriable?(%RuntimeError{}, none_policy)
      refute ErrorClassifier.retriable?({:error, :timeout}, none_policy)
    end
  end
end
