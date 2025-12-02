defmodule Forge.ErrorClassifierTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.{ErrorClassifier, RetryPolicy}

  describe "retriable?/2 with :all policy" do
    test "returns true for any error" do
      policy = RetryPolicy.new(retriable_errors: :all)

      assert ErrorClassifier.retriable?(429, policy)
      assert ErrorClassifier.retriable?(500, policy)
      assert ErrorClassifier.retriable?(%RuntimeError{}, policy)
      assert ErrorClassifier.retriable?({:error, :timeout}, policy)
      assert ErrorClassifier.retriable?("any error", policy)
    end
  end

  describe "retriable?/2 with :none policy" do
    test "returns false for any error" do
      policy = RetryPolicy.new(retriable_errors: :none)

      refute ErrorClassifier.retriable?(429, policy)
      refute ErrorClassifier.retriable?(500, policy)
      refute ErrorClassifier.retriable?(%RuntimeError{}, policy)
      refute ErrorClassifier.retriable?({:error, :timeout}, policy)
    end
  end

  describe "retriable?/2 with HTTP status code list" do
    test "returns true for listed status codes" do
      policy = RetryPolicy.new(retriable_errors: [429, 500, 502, 503, 504])

      assert ErrorClassifier.retriable?(429, policy)
      assert ErrorClassifier.retriable?(500, policy)
      assert ErrorClassifier.retriable?(502, policy)
      assert ErrorClassifier.retriable?(503, policy)
      assert ErrorClassifier.retriable?(504, policy)
    end

    test "returns false for unlisted status codes" do
      policy = RetryPolicy.new(retriable_errors: [429, 500])

      refute ErrorClassifier.retriable?(400, policy)
      refute ErrorClassifier.retriable?(404, policy)
      refute ErrorClassifier.retriable?(503, policy)
    end
  end

  describe "retriable?/2 with exception module list" do
    test "returns true for listed exception types" do
      policy = RetryPolicy.new(retriable_errors: [RuntimeError, ArgumentError])

      assert ErrorClassifier.retriable?(%RuntimeError{message: "oops"}, policy)
      assert ErrorClassifier.retriable?(%ArgumentError{message: "bad arg"}, policy)
    end

    test "returns false for unlisted exception types" do
      policy = RetryPolicy.new(retriable_errors: [RuntimeError])

      refute ErrorClassifier.retriable?(%ArgumentError{message: "bad arg"}, policy)
      refute ErrorClassifier.retriable?(%KeyError{key: :foo}, policy)
    end
  end

  describe "retriable?/2 with error tuple atoms" do
    test "returns true for listed error atoms" do
      policy = RetryPolicy.new(retriable_errors: [:timeout, :econnrefused, :closed])

      assert ErrorClassifier.retriable?({:error, :timeout}, policy)
      assert ErrorClassifier.retriable?({:error, :econnrefused}, policy)
      assert ErrorClassifier.retriable?({:error, :closed}, policy)
    end

    test "returns false for unlisted error atoms" do
      policy = RetryPolicy.new(retriable_errors: [:timeout])

      refute ErrorClassifier.retriable?({:error, :econnrefused}, policy)
      refute ErrorClassifier.retriable?({:error, :nxdomain}, policy)
    end
  end

  describe "retriable?/2 with mixed list" do
    test "handles mix of status codes, exceptions, and atoms" do
      policy =
        RetryPolicy.new(retriable_errors: [429, RuntimeError, :timeout, :econnrefused])

      # HTTP status codes
      assert ErrorClassifier.retriable?(429, policy)
      refute ErrorClassifier.retriable?(404, policy)

      # Exceptions
      assert ErrorClassifier.retriable?(%RuntimeError{}, policy)
      refute ErrorClassifier.retriable?(%ArgumentError{}, policy)

      # Error tuples
      assert ErrorClassifier.retriable?({:error, :timeout}, policy)
      assert ErrorClassifier.retriable?({:error, :econnrefused}, policy)
      refute ErrorClassifier.retriable?({:error, :closed}, policy)
    end
  end

  describe "retriable?/2 with unknown error format" do
    test "returns false for unhandled error types when list specified" do
      policy = RetryPolicy.new(retriable_errors: [429])

      refute ErrorClassifier.retriable?("string error", policy)
      refute ErrorClassifier.retriable?({:ok, :weird}, policy)
      refute ErrorClassifier.retriable?(%{custom: :error}, policy)
    end
  end
end
