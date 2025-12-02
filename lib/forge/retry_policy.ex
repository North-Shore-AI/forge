defmodule Forge.RetryPolicy do
  @moduledoc """
  Retry policy configuration for stage execution.

  Defines retry behavior including max attempts, backoff strategy, and which
  errors are retriable. Based on ADR-003.

  ## Backoff Strategies

    * `:jittered_exponential` - Exponential backoff with ±25% jitter to avoid thundering herd
    * `:fixed` - Constant delay between retries
    * `:linear` - Linear increase in delay

  ## Examples

      # Default policy: 3 attempts with jittered exponential backoff
      policy = Forge.RetryPolicy.new()

      # Custom policy for LLM API calls
      policy = Forge.RetryPolicy.new(
        max_attempts: 5,
        backoff: :jittered_exponential,
        base_delay_ms: 1000,
        max_delay_ms: 30_000,
        retriable_errors: [429, 500, 502, 503, 504]
      )

      # No retries for deterministic stages
      policy = Forge.RetryPolicy.new(max_attempts: 1)
  """

  @type backoff_strategy :: :jittered_exponential | :fixed | :linear
  @type retriable_errors :: :all | :none | [integer() | module() | atom()]

  @type t :: %__MODULE__{
          max_attempts: pos_integer(),
          backoff: backoff_strategy(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          retriable_errors: retriable_errors()
        }

  @enforce_keys [:max_attempts, :backoff, :base_delay_ms, :max_delay_ms, :retriable_errors]
  defstruct [
    :max_attempts,
    :backoff,
    :base_delay_ms,
    :max_delay_ms,
    :retriable_errors
  ]

  @doc """
  Creates a new retry policy with given options.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:backoff` - Backoff strategy (default: :jittered_exponential)
    * `:base_delay_ms` - Base delay in milliseconds (default: 1000)
    * `:max_delay_ms` - Maximum delay in milliseconds (default: 60_000)
    * `:retriable_errors` - Which errors to retry (default: :all)
      - `:all` - Retry all errors
      - `:none` - Don't retry any errors
      - List of HTTP status codes, exception modules, or error atoms
  """
  def new(opts \\ []) do
    %__MODULE__{
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      backoff: Keyword.get(opts, :backoff, :jittered_exponential),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, 1000),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, 60_000),
      retriable_errors: Keyword.get(opts, :retriable_errors, :all)
    }
  end

  @doc """
  Returns the default retry policy as specified in ADR-003.
  """
  def default do
    new()
  end

  @doc """
  Computes the delay in milliseconds for a given attempt.

  ## Examples

      iex> policy = Forge.RetryPolicy.new(backoff: :fixed, base_delay_ms: 500)
      iex> Forge.RetryPolicy.compute_delay(1, policy)
      500

      iex> policy = Forge.RetryPolicy.new(backoff: :linear, base_delay_ms: 1000)
      iex> Forge.RetryPolicy.compute_delay(2, policy)
      2000
  """
  def compute_delay(attempt, %__MODULE__{} = policy) do
    case policy.backoff do
      :jittered_exponential ->
        compute_jittered_exponential(attempt, policy)

      :fixed ->
        policy.base_delay_ms

      :linear ->
        min(policy.base_delay_ms * attempt, policy.max_delay_ms)
    end
  end

  defp compute_jittered_exponential(attempt, policy) do
    # Base exponential: base * 2^(attempt-1)
    base = policy.base_delay_ms * :math.pow(2, attempt - 1)

    # Cap at max_delay_ms
    capped = min(base, policy.max_delay_ms)

    # Add ±25% jitter (0.75 to 1.25 multiplier)
    jitter = capped * (0.75 + :rand.uniform() * 0.5)

    round(jitter)
  end
end
