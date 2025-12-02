defmodule Forge.RetryPolicyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.RetryPolicy

  describe "new/1" do
    test "creates policy with defaults" do
      policy = RetryPolicy.new()

      assert policy.max_attempts == 3
      assert policy.backoff == :jittered_exponential
      assert policy.base_delay_ms == 1000
      assert policy.max_delay_ms == 60_000
      assert policy.retriable_errors == :all
    end

    test "creates policy with custom options" do
      policy =
        RetryPolicy.new(
          max_attempts: 5,
          backoff: :fixed,
          base_delay_ms: 500,
          max_delay_ms: 10_000,
          retriable_errors: [429, 503]
        )

      assert policy.max_attempts == 5
      assert policy.backoff == :fixed
      assert policy.base_delay_ms == 500
      assert policy.max_delay_ms == 10_000
      assert policy.retriable_errors == [429, 503]
    end

    test "accepts :none for no retries" do
      policy = RetryPolicy.new(max_attempts: 1)

      assert policy.max_attempts == 1
    end
  end

  describe "compute_delay/2 with jittered_exponential" do
    test "computes exponential backoff with jitter for attempt 1" do
      policy = RetryPolicy.new(backoff: :jittered_exponential, base_delay_ms: 1000)

      # Run multiple times to test jitter variance
      delays =
        for _ <- 1..100 do
          RetryPolicy.compute_delay(1, policy)
        end

      # Attempt 1: base = 1000 * 2^0 = 1000
      # With ±25% jitter: 750-1250
      assert Enum.all?(delays, &(&1 >= 750 and &1 <= 1250))

      # Mean should be close to 1000
      mean = Enum.sum(delays) / length(delays)
      assert_in_delta mean, 1000, 100
    end

    test "computes exponential backoff with jitter for attempt 2" do
      policy = RetryPolicy.new(backoff: :jittered_exponential, base_delay_ms: 1000)

      delays =
        for _ <- 1..100 do
          RetryPolicy.compute_delay(2, policy)
        end

      # Attempt 2: base = 1000 * 2^1 = 2000
      # With ±25% jitter: 1500-2500
      assert Enum.all?(delays, &(&1 >= 1500 and &1 <= 2500))

      mean = Enum.sum(delays) / length(delays)
      assert_in_delta mean, 2000, 150
    end

    test "computes exponential backoff with jitter for attempt 3" do
      policy = RetryPolicy.new(backoff: :jittered_exponential, base_delay_ms: 1000)

      delays =
        for _ <- 1..100 do
          RetryPolicy.compute_delay(3, policy)
        end

      # Attempt 3: base = 1000 * 2^2 = 4000
      # With ±25% jitter: 3000-5000
      assert Enum.all?(delays, &(&1 >= 3000 and &1 <= 5000))

      mean = Enum.sum(delays) / length(delays)
      assert_in_delta mean, 4000, 200
    end

    test "respects max_delay_ms cap" do
      policy =
        RetryPolicy.new(
          backoff: :jittered_exponential,
          base_delay_ms: 1000,
          max_delay_ms: 3000
        )

      # Attempt 5: base would be 16000, but capped at 3000
      delays =
        for _ <- 1..100 do
          RetryPolicy.compute_delay(5, policy)
        end

      # With ±25% jitter on 3000: 2250-3750
      assert Enum.all?(delays, &(&1 >= 2250 and &1 <= 3750))
    end
  end

  describe "compute_delay/2 with fixed" do
    test "returns constant delay" do
      policy = RetryPolicy.new(backoff: :fixed, base_delay_ms: 500)

      assert RetryPolicy.compute_delay(1, policy) == 500
      assert RetryPolicy.compute_delay(2, policy) == 500
      assert RetryPolicy.compute_delay(3, policy) == 500
      assert RetryPolicy.compute_delay(10, policy) == 500
    end
  end

  describe "compute_delay/2 with linear" do
    test "computes linear backoff" do
      policy = RetryPolicy.new(backoff: :linear, base_delay_ms: 1000)

      assert RetryPolicy.compute_delay(1, policy) == 1000
      assert RetryPolicy.compute_delay(2, policy) == 2000
      assert RetryPolicy.compute_delay(3, policy) == 3000
      assert RetryPolicy.compute_delay(5, policy) == 5000
    end

    test "respects max_delay_ms cap" do
      policy =
        RetryPolicy.new(backoff: :linear, base_delay_ms: 1000, max_delay_ms: 2500)

      assert RetryPolicy.compute_delay(1, policy) == 1000
      assert RetryPolicy.compute_delay(2, policy) == 2000
      assert RetryPolicy.compute_delay(3, policy) == 2500
      assert RetryPolicy.compute_delay(10, policy) == 2500
    end
  end

  describe "default/0" do
    test "returns default policy matching ADR spec" do
      policy = RetryPolicy.default()

      assert policy.max_attempts == 3
      assert policy.backoff == :jittered_exponential
      assert policy.base_delay_ms == 1000
      assert policy.max_delay_ms == 60_000
      assert policy.retriable_errors == :all
    end
  end
end
