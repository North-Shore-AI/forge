defmodule Forge.AnvilBridge.MockTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.AnvilBridge.Mock

  setup do
    # Start or reset the mock adapter
    Mock.reset()
    :ok
  end

  describe "publish_sample/2" do
    test "publishes a sample and returns job ID" do
      sample = build_sample("sample-1")

      {:ok, job_id} = Mock.publish_sample(sample, queue: "test_queue")

      assert is_binary(job_id)
      assert job_id =~ "job-"
    end

    test "stores published sample in state" do
      sample = build_sample("sample-2")

      {:ok, _job_id} = Mock.publish_sample(sample, queue: "test_queue")

      state = Mock.get_state()
      assert length(state.jobs) == 1
      published_job = hd(state.jobs)
      assert published_job.sample_id == "sample-2"
    end

    test "adds sample to specified queue" do
      sample = build_sample("sample-3")

      {:ok, _job_id} = Mock.publish_sample(sample, queue: "cns_narratives")

      state = Mock.get_state()
      assert Map.has_key?(state.queues, "cns_narratives")
      assert length(state.queues["cns_narratives"]) == 1
    end

    test "converts sample to DTO format" do
      sample =
        build_sample("sample-4", %{
          "claim" => "Test claim",
          "narrative_a" => "Narrative A"
        })

      {:ok, _job_id} = Mock.publish_sample(sample, queue: "test_queue")

      state = Mock.get_state()
      job = hd(state.jobs)
      assert job.title == "Claim: Test claim..."
      assert job.metadata.pipeline_id == "pipeline-test"
    end

    test "includes measurements by default" do
      sample = build_sample("sample-5", %{}, %{"metric" => 42})

      {:ok, _job_id} = Mock.publish_sample(sample, queue: "test_queue")

      state = Mock.get_state()
      job = hd(state.jobs)
      assert job.metadata.measurements == %{"metric" => 42}
    end

    test "excludes measurements when include_measurements is false" do
      sample = build_sample("sample-6", %{}, %{"metric" => 42})

      {:ok, _job_id} =
        Mock.publish_sample(sample, queue: "test_queue", include_measurements: false)

      state = Mock.get_state()
      job = hd(state.jobs)
      assert job.metadata.measurements == %{}
    end

    test "requires queue option" do
      sample = build_sample("sample-7")

      assert_raise KeyError, fn ->
        Mock.publish_sample(sample, [])
      end
    end
  end

  describe "publish_batch/2" do
    test "publishes multiple samples" do
      samples = [
        build_sample("sample-1"),
        build_sample("sample-2"),
        build_sample("sample-3")
      ]

      {:ok, count} = Mock.publish_batch(samples, queue: "test_queue")

      assert count == 3
    end

    test "stores all samples in state" do
      samples = [
        build_sample("sample-10"),
        build_sample("sample-11")
      ]

      {:ok, _count} = Mock.publish_batch(samples, queue: "test_queue")

      state = Mock.get_state()
      assert length(state.jobs) == 2
    end

    test "adds all samples to specified queue" do
      samples = [
        build_sample("sample-20"),
        build_sample("sample-21"),
        build_sample("sample-22")
      ]

      {:ok, _count} = Mock.publish_batch(samples, queue: "batch_queue")

      state = Mock.get_state()
      assert length(state.queues["batch_queue"]) == 3
    end

    test "generates unique job IDs for each sample" do
      samples = [
        build_sample("sample-30"),
        build_sample("sample-31")
      ]

      {:ok, _count} = Mock.publish_batch(samples, queue: "test_queue")

      state = Mock.get_state()
      job_ids = Enum.map(state.jobs, & &1.job_id)
      assert length(Enum.uniq(job_ids)) == 2
    end

    test "handles empty batch" do
      {:ok, count} = Mock.publish_batch([], queue: "test_queue")

      assert count == 0
    end
  end

  describe "get_labels/1" do
    test "returns labels for a sample" do
      sample_id = "sample-100"

      labels = [
        %{label: "entailment", annotator_id: "user-1", confidence: 1.0},
        %{label: "neutral", annotator_id: "user-2", confidence: 0.8}
      ]

      Mock.add_labels(sample_id, labels)

      {:ok, retrieved_labels} = Mock.get_labels(sample_id)

      assert length(retrieved_labels) == 2
      assert Enum.any?(retrieved_labels, &(&1.label == "entailment"))
      assert Enum.any?(retrieved_labels, &(&1.label == "neutral"))
    end

    test "returns error when sample has no labels" do
      {:error, :not_found} = Mock.get_labels("nonexistent-sample")
    end

    test "returns empty list as not_found" do
      sample_id = "sample-101"
      Mock.add_labels(sample_id, [])

      {:error, :not_found} = Mock.get_labels(sample_id)
    end
  end

  describe "sync_labels/2" do
    test "returns count of labels synced" do
      sample_id = "sample-200"

      labels = [
        %{label: "entailment", annotator_id: "user-1", confidence: 1.0},
        %{label: "neutral", annotator_id: "user-2", confidence: 0.9}
      ]

      Mock.add_labels(sample_id, labels)

      {:ok, count} = Mock.sync_labels(sample_id)

      assert count == 2
    end

    test "returns 0 when sample has no labels" do
      {:ok, count} = Mock.sync_labels("nonexistent-sample")

      assert count == 0
    end
  end

  describe "create_queue_for_pipeline/2" do
    test "creates a queue with pipeline ID as name" do
      pipeline_id = "pipeline-abc-123"

      {:ok, queue_name} = Mock.create_queue_for_pipeline(pipeline_id, [])

      assert queue_name == pipeline_id
    end

    test "creates a queue with custom name" do
      pipeline_id = "pipeline-xyz-456"

      {:ok, queue_name} =
        Mock.create_queue_for_pipeline(
          pipeline_id,
          queue_name: "custom_queue"
        )

      assert queue_name == "custom_queue"
    end

    test "stores queue metadata" do
      pipeline_id = "pipeline-def-789"
      description = "Test queue for pipeline"

      {:ok, _queue_name} =
        Mock.create_queue_for_pipeline(
          pipeline_id,
          description: description,
          priority: "high"
        )

      state = Mock.get_state()
      queue_info = state.queue_metadata[pipeline_id]
      assert queue_info.pipeline_id == pipeline_id
      assert queue_info.description == description
      assert queue_info.priority == "high"
    end

    test "uses default description and priority" do
      pipeline_id = "pipeline-ghi-999"

      {:ok, _queue_name} = Mock.create_queue_for_pipeline(pipeline_id, [])

      state = Mock.get_state()
      queue_info = state.queue_metadata[pipeline_id]
      assert queue_info.description =~ "pipeline"
      assert queue_info.priority == "normal"
    end
  end

  describe "get_queue_stats/1" do
    test "returns stats for an empty queue" do
      {:ok, stats} = Mock.get_queue_stats("empty_queue")

      assert stats.total == 0
      assert stats.completed == 0
      assert stats.pending == 0
      assert stats.in_progress == 0
    end

    test "returns stats for a queue with samples" do
      samples = [
        build_sample("sample-1"),
        build_sample("sample-2"),
        build_sample("sample-3")
      ]

      {:ok, _count} = Mock.publish_batch(samples, queue: "stats_queue")

      {:ok, stats} = Mock.get_queue_stats("stats_queue")

      assert stats.total == 3
      assert stats.pending == 3
    end

    test "tracks completed jobs" do
      sample = build_sample("sample-complete")
      {:ok, job_id} = Mock.publish_sample(sample, queue: "complete_queue")

      Mock.complete_job(job_id)

      {:ok, stats} = Mock.get_queue_stats("complete_queue")

      assert stats.total == 1
      assert stats.completed == 1
    end
  end

  describe "complete_job/1" do
    test "marks a job as completed" do
      sample = build_sample("sample-job-1")
      {:ok, job_id} = Mock.publish_sample(sample, queue: "test_queue")

      Mock.complete_job(job_id)

      state = Mock.get_state()
      job = Enum.find(state.jobs, &(&1.job_id == job_id))
      assert job.completed == true
    end

    test "updates job in queue" do
      sample = build_sample("sample-job-2")
      {:ok, job_id} = Mock.publish_sample(sample, queue: "test_queue")

      Mock.complete_job(job_id)

      state = Mock.get_state()
      job = Enum.find(state.queues["test_queue"], &(&1.job_id == job_id))
      assert job.completed == true
    end
  end

  describe "reset/0" do
    test "clears all state" do
      samples = [build_sample("sample-1"), build_sample("sample-2")]
      {:ok, _count} = Mock.publish_batch(samples, queue: "test_queue")

      Mock.reset()

      state = Mock.get_state()
      assert state.jobs == []
      assert state.queues == %{}
      assert state.labels == %{}
      assert state.queue_metadata == %{}
    end

    test "allows publishing after reset" do
      Mock.publish_sample(build_sample("sample-1"), queue: "queue-1")
      Mock.reset()

      {:ok, _job_id} = Mock.publish_sample(build_sample("sample-2"), queue: "queue-2")

      state = Mock.get_state()
      assert length(state.jobs) == 1
    end
  end

  # Helper functions

  defp build_sample(id, data \\ %{}, measurements \\ %{}) do
    %{
      id: id,
      pipeline_id: "pipeline-test",
      data: Map.merge(%{"text" => "Default text"}, data),
      measurements: measurements
    }
  end
end
