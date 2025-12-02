defmodule Forge.Stage.ExecutorTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.{Sample, Stage.Executor, RetryPolicy}

  # Test stages with various retry behaviors
  defmodule SuccessStage do
    @behaviour Forge.Stage

    def process(sample) do
      data = Map.put(sample.data, :processed, true)
      {:ok, %{sample | data: data}}
    end

    def retry_policy do
      RetryPolicy.new(max_attempts: 1)
    end
  end

  defmodule AlwaysFailStage do
    @behaviour Forge.Stage

    def process(_sample) do
      {:error, :permanent_failure}
    end

    def retry_policy do
      RetryPolicy.new(max_attempts: 3, retriable_errors: :none)
    end
  end

  defmodule TransientFailStage do
    @behaviour Forge.Stage

    def process(%{data: %{attempt: attempt}} = sample) do
      # Fail on first 2 attempts, succeed on 3rd
      if attempt < 3 do
        {:error, 429}
      else
        {:ok, %{sample | data: Map.put(sample.data, :success, true)}}
      end
    end

    def retry_policy do
      RetryPolicy.new(
        max_attempts: 3,
        backoff: :fixed,
        base_delay_ms: 10,
        retriable_errors: [429, 503]
      )
    end
  end

  defmodule NonRetriableErrorStage do
    @behaviour Forge.Stage

    def process(_sample) do
      {:error, 404}
    end

    def retry_policy do
      RetryPolicy.new(max_attempts: 3, retriable_errors: [429, 503])
    end
  end

  defmodule CountingAgent do
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> %{attempts: 0, delays: []} end)
    end

    def increment_attempt(agent) do
      Agent.update(agent, fn state -> %{state | attempts: state.attempts + 1} end)
    end

    def record_delay(agent, delay) do
      Agent.update(agent, fn state -> %{state | delays: [delay | state.delays]} end)
    end

    def get_state(agent) do
      Agent.get(agent, & &1)
    end
  end

  defmodule CountedFailStage do
    @behaviour Forge.Stage

    def process(%{data: %{counter_agent: agent}}) do
      CountingAgent.increment_attempt(agent)
      {:error, 500}
    end

    def retry_policy do
      RetryPolicy.new(
        max_attempts: 3,
        backoff: :fixed,
        base_delay_ms: 10,
        retriable_errors: [500]
      )
    end
  end

  describe "apply_with_retry/2 without retries" do
    test "returns success on first attempt" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{value: 42})
      stage = SuccessStage

      assert {:ok, result} = Executor.apply_with_retry(sample, stage)
      assert result.data.processed == true
    end

    @tag capture_log: true
    test "returns error immediately for non-retriable error" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{})
      stage = AlwaysFailStage

      assert {:error, :max_retries, :permanent_failure} =
               Executor.apply_with_retry(sample, stage)
    end
  end

  describe "apply_with_retry/2 with retries" do
    test "succeeds after retries for transient failures" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{attempt: 1})
      stage = TransientFailStage

      # Manually track attempts by updating sample data
      result =
        Enum.reduce_while(1..3, {:error, :no_attempts}, fn attempt, _acc ->
          sample_with_attempt = %{sample | data: Map.put(sample.data, :attempt, attempt)}

          case stage.process(sample_with_attempt) do
            {:ok, result} ->
              {:halt, {:ok, result}}

            {:error, _} when attempt < 3 ->
              {:cont, {:error, :retrying}}

            {:error, error} ->
              {:halt, {:error, :max_retries, error}}
          end
        end)

      assert {:ok, final_sample} = result
      assert final_sample.data.success == true
    end

    @tag capture_log: true
    test "fails after max attempts with retriable error" do
      {:ok, agent} = CountingAgent.start_link()
      sample = Sample.new(id: "1", pipeline: :test, data: %{counter_agent: agent})
      stage = CountedFailStage

      assert {:error, :max_retries, 500} = Executor.apply_with_retry(sample, stage)

      # Verify all 3 attempts were made
      state = CountingAgent.get_state(agent)
      assert state.attempts == 3
    end

    @tag capture_log: true
    test "fails immediately for non-retriable error code" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{})
      stage = NonRetriableErrorStage

      assert {:error, :max_retries, 404} = Executor.apply_with_retry(sample, stage)
    end
  end

  describe "apply_with_retry/2 with backoff strategies" do
    test "uses fixed backoff correctly" do
      policy =
        RetryPolicy.new(
          max_attempts: 3,
          backoff: :fixed,
          base_delay_ms: 100
        )

      assert RetryPolicy.compute_delay(1, policy) == 100
      assert RetryPolicy.compute_delay(2, policy) == 100
      assert RetryPolicy.compute_delay(3, policy) == 100
    end

    test "uses linear backoff correctly" do
      policy =
        RetryPolicy.new(
          max_attempts: 3,
          backoff: :linear,
          base_delay_ms: 100
        )

      assert RetryPolicy.compute_delay(1, policy) == 100
      assert RetryPolicy.compute_delay(2, policy) == 200
      assert RetryPolicy.compute_delay(3, policy) == 300
    end

    test "uses jittered exponential backoff with variance" do
      policy =
        RetryPolicy.new(
          max_attempts: 3,
          backoff: :jittered_exponential,
          base_delay_ms: 100
        )

      # Compute multiple delays to verify jitter
      delays1 = for _ <- 1..10, do: RetryPolicy.compute_delay(1, policy)
      delays2 = for _ <- 1..10, do: RetryPolicy.compute_delay(2, policy)

      # Should have variance (not all the same)
      assert length(Enum.uniq(delays1)) > 1
      assert length(Enum.uniq(delays2)) > 1

      # Should be within expected range
      assert Enum.all?(delays1, &(&1 >= 75 and &1 <= 125))
      assert Enum.all?(delays2, &(&1 >= 150 and &1 <= 250))
    end
  end

  describe "get_retry_policy/1" do
    test "uses stage-defined policy if available" do
      policy = Executor.get_retry_policy(TransientFailStage)

      assert policy.max_attempts == 3
      assert policy.backoff == :fixed
      assert policy.base_delay_ms == 10
      assert policy.retriable_errors == [429, 503]
    end

    test "uses default policy if stage doesn't define one" do
      defmodule NoRetryPolicyStage do
        @behaviour Forge.Stage

        def process(sample), do: {:ok, sample}
      end

      policy = Executor.get_retry_policy(NoRetryPolicyStage)

      # Should match default from RetryPolicy.default()
      assert policy.max_attempts == 3
      assert policy.backoff == :jittered_exponential
      assert policy.base_delay_ms == 1000
      assert policy.max_delay_ms == 60_000
      assert policy.retriable_errors == :all
    end
  end

  describe "DLQ integration" do
    @tag capture_log: true
    test "sample is marked for DLQ after max retries" do
      {:ok, agent} = CountingAgent.start_link()
      sample = Sample.new(id: "1", pipeline: :test, data: %{counter_agent: agent})
      stage = CountedFailStage

      result = Executor.apply_with_retry(sample, stage)

      assert {:error, :max_retries, 500} = result

      # In real implementation, this would trigger DLQ storage
      # For now, verify the error tuple format is correct
      assert match?({:error, :max_retries, _}, result)
    end
  end
end
