defmodule Forge.ErrorClassifier do
  @moduledoc """
  Classifies errors as retriable or non-retriable based on retry policy.

  Based on ADR-003, determines whether an error should trigger a retry attempt
  or immediately fail.

  ## Examples

      # Retry all errors
      policy = Forge.RetryPolicy.new(retriable_errors: :all)
      Forge.ErrorClassifier.retriable?(429, policy)
      #=> true

      # Retry specific HTTP status codes
      policy = Forge.RetryPolicy.new(retriable_errors: [429, 500, 503])
      Forge.ErrorClassifier.retriable?(429, policy)
      #=> true
      Forge.ErrorClassifier.retriable?(404, policy)
      #=> false

      # Retry specific exception types
      policy = Forge.RetryPolicy.new(retriable_errors: [RuntimeError, ArgumentError])
      Forge.ErrorClassifier.retriable?(%RuntimeError{}, policy)
      #=> true

      # Retry error tuples with specific atoms
      policy = Forge.RetryPolicy.new(retriable_errors: [:timeout, :econnrefused])
      Forge.ErrorClassifier.retriable?({:error, :timeout}, policy)
      #=> true
  """

  alias Forge.RetryPolicy

  @doc """
  Determines if an error is retriable based on the retry policy.

  Returns `true` if the error should be retried, `false` otherwise.

  ## Error Types

  Supports classification of:
    * HTTP status codes (integers like 429, 500, 503)
    * Exception structs (like %RuntimeError{})
    * Error tuples (like {:error, :timeout})
    * Custom error values (matched against policy list)
  """
  def retriable?(_error, %RetryPolicy{retriable_errors: :all}), do: true
  def retriable?(_error, %RetryPolicy{retriable_errors: :none}), do: false

  def retriable?(error, %RetryPolicy{retriable_errors: error_list}) when is_list(error_list) do
    cond do
      # HTTP status code
      is_integer(error) ->
        error in error_list

      # Exception struct
      is_exception(error) ->
        error.__struct__ in error_list

      # Error tuple like {:error, :timeout}
      is_tuple(error) and tuple_size(error) == 2 ->
        match_error_tuple?(error, error_list)

      # Unknown error type
      true ->
        false
    end
  end

  defp match_error_tuple?({:error, reason}, error_list) when is_atom(reason) do
    reason in error_list
  end

  defp match_error_tuple?(_, _), do: false
end
