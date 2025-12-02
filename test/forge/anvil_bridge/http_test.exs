defmodule Forge.AnvilBridge.HTTPTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.AnvilBridge.HTTP

  describe "publish_sample/2" do
    test "returns not_available until HTTP API is implemented" do
      sample = build_sample("sample-1")

      {:error, :not_available} = HTTP.publish_sample(sample, queue: "test_queue")
    end
  end

  describe "publish_batch/2" do
    test "returns not_available until HTTP API is implemented" do
      samples = [build_sample("sample-1"), build_sample("sample-2")]

      {:error, :not_available} = HTTP.publish_batch(samples, queue: "test_queue")
    end
  end

  describe "get_labels/1" do
    test "returns not_available until HTTP API is implemented" do
      {:error, :not_available} = HTTP.get_labels("sample-123")
    end
  end

  describe "sync_labels/2" do
    test "returns not_available until HTTP API is implemented" do
      {:error, :not_available} = HTTP.sync_labels("sample-123", [])
    end
  end

  describe "create_queue_for_pipeline/2" do
    test "returns not_available until HTTP API is implemented" do
      {:error, :not_available} = HTTP.create_queue_for_pipeline("pipeline-123", [])
    end
  end

  describe "get_queue_stats/1" do
    test "returns not_available until HTTP API is implemented" do
      {:error, :not_available} = HTTP.get_queue_stats("test_queue")
    end
  end

  # Helper functions

  defp build_sample(id) do
    %{
      id: id,
      pipeline_id: "pipeline-test",
      data: %{"text" => "Test content"},
      measurements: %{}
    }
  end
end
