defmodule Forge.TelemetryTest do
  use ExUnit.Case, async: true

  alias Forge.Telemetry

  describe "telemetry events" do
    test "emits pipeline start event" do
      test_pid = self()

      :telemetry.attach(
        "test-pipeline-start",
        [:forge, :pipeline, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      pipeline_id = "test-pipeline-id"
      run_id = "test-run-id"
      name = :test_pipeline

      Telemetry.pipeline_start(pipeline_id, run_id, name)

      assert_receive {:telemetry_event, [:forge, :pipeline, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.pipeline_id == pipeline_id
      assert metadata.run_id == run_id
      assert metadata.name == name

      :telemetry.detach("test-pipeline-start")
    end

    test "emits pipeline stop event" do
      test_pid = self()

      :telemetry.attach(
        "test-pipeline-stop",
        [:forge, :pipeline, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      pipeline_id = "test-pipeline-id"
      run_id = "test-run-id"
      duration = 1_000_000

      Telemetry.pipeline_stop(pipeline_id, run_id, duration, :completed, 10)

      assert_receive {:telemetry_event, [:forge, :pipeline, :stop], measurements, metadata}
      assert measurements.duration == duration
      assert measurements.samples_processed == 10
      assert metadata.pipeline_id == pipeline_id
      assert metadata.run_id == run_id
      assert metadata.outcome == :completed

      :telemetry.detach("test-pipeline-stop")
    end

    test "emits pipeline exception event" do
      test_pid = self()

      :telemetry.attach(
        "test-pipeline-exception",
        [:forge, :pipeline, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      pipeline_id = "test-pipeline-id"
      run_id = "test-run-id"
      duration = 500_000

      Telemetry.pipeline_exception(pipeline_id, run_id, duration, RuntimeError)

      assert_receive {:telemetry_event, [:forge, :pipeline, :exception], measurements, metadata}
      assert measurements.duration == duration
      assert metadata.pipeline_id == pipeline_id
      assert metadata.run_id == run_id
      assert metadata.exception == RuntimeError

      :telemetry.detach("test-pipeline-exception")
    end

    test "emits stage start event" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-start",
        [:forge, :stage, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      stage = "MyStage"
      pipeline_id = "pipeline-1"
      run_id = "run-1"

      Telemetry.stage_start(sample_id, stage, pipeline_id, run_id)

      assert_receive {:telemetry_event, [:forge, :stage, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.sample_id == sample_id
      assert metadata.stage == stage
      assert metadata.pipeline_id == pipeline_id
      assert metadata.run_id == run_id

      :telemetry.detach("test-stage-start")
    end

    test "emits stage stop event with success" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-stop",
        [:forge, :stage, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      stage = "MyStage"
      duration = 2_000_000

      Telemetry.stage_stop(sample_id, stage, duration, :success, nil)

      assert_receive {:telemetry_event, [:forge, :stage, :stop], measurements, metadata}
      assert measurements.duration == duration
      assert metadata.sample_id == sample_id
      assert metadata.stage == stage
      assert metadata.outcome == :success
      refute Map.has_key?(metadata, :error_type)

      :telemetry.detach("test-stage-stop")
    end

    test "emits stage stop event with error" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-stop-error",
        [:forge, :stage, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      stage = "MyStage"
      duration = 1_500_000

      Telemetry.stage_stop(sample_id, stage, duration, :error, :network_error)

      assert_receive {:telemetry_event, [:forge, :stage, :stop], measurements, metadata}
      assert measurements.duration == duration
      assert metadata.outcome == :error
      assert metadata.error_type == :network_error

      :telemetry.detach("test-stage-stop-error")
    end

    test "emits stage retry event" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-retry",
        [:forge, :stage, :retry],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      stage = "MyStage"
      attempt = 2
      delay_ms = 1000
      error = "Connection timeout"

      Telemetry.stage_retry(sample_id, stage, attempt, delay_ms, error)

      assert_receive {:telemetry_event, [:forge, :stage, :retry], measurements, metadata}
      assert measurements.attempt == attempt
      assert measurements.delay_ms == delay_ms
      assert metadata.sample_id == sample_id
      assert metadata.stage == stage
      assert metadata.error == error

      :telemetry.detach("test-stage-retry")
    end

    test "emits measurement start event" do
      test_pid = self()

      :telemetry.attach(
        "test-measurement-start",
        [:forge, :measurement, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      measurement_key = "embedding"
      version = "v1"

      Telemetry.measurement_start(sample_id, measurement_key, version)

      assert_receive {:telemetry_event, [:forge, :measurement, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.sample_id == sample_id
      assert metadata.measurement_key == measurement_key
      assert metadata.version == version

      :telemetry.detach("test-measurement-start")
    end

    test "emits measurement stop event" do
      test_pid = self()

      :telemetry.attach(
        "test-measurement-stop",
        [:forge, :measurement, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      measurement_key = "embedding"
      duration = 5_000_000
      outcome = :computed

      Telemetry.measurement_stop(sample_id, measurement_key, duration, outcome)

      assert_receive {:telemetry_event, [:forge, :measurement, :stop], measurements, metadata}
      assert measurements.duration == duration
      assert metadata.sample_id == sample_id
      assert metadata.measurement_key == measurement_key
      assert metadata.outcome == outcome

      :telemetry.detach("test-measurement-stop")
    end

    test "emits storage sample write event" do
      test_pid = self()

      :telemetry.attach(
        "test-storage-write",
        [:forge, :storage, :sample_write],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      duration = 3_000_000
      size_bytes = 1024
      backend = :postgres

      Telemetry.storage_sample_write(sample_id, duration, size_bytes, backend)

      assert_receive {:telemetry_event, [:forge, :storage, :sample_write], measurements, metadata}
      assert measurements.duration == duration
      assert measurements.size_bytes == size_bytes
      assert metadata.sample_id == sample_id
      assert metadata.storage_backend == backend

      :telemetry.detach("test-storage-write")
    end

    test "emits storage artifact upload event" do
      test_pid = self()

      :telemetry.attach(
        "test-artifact-upload",
        [:forge, :storage, :artifact_upload],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      artifact_key = "narrative/sample-123"
      duration = 10_000_000
      size_bytes = 4096
      deduplication = true

      Telemetry.storage_artifact_upload(artifact_key, duration, size_bytes, deduplication)

      assert_receive {:telemetry_event, [:forge, :storage, :artifact_upload], measurements,
                      metadata}

      assert measurements.duration == duration
      assert measurements.size_bytes == size_bytes
      assert metadata.artifact_key == artifact_key
      assert metadata.deduplication == deduplication

      :telemetry.detach("test-artifact-upload")
    end

    test "emits storage artifact download event" do
      test_pid = self()

      :telemetry.attach(
        "test-artifact-download",
        [:forge, :storage, :artifact_download],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      artifact_key = "narrative/sample-123"
      duration = 8_000_000
      size_bytes = 4096

      Telemetry.storage_artifact_download(artifact_key, duration, size_bytes)

      assert_receive {:telemetry_event, [:forge, :storage, :artifact_download], measurements,
                      metadata}

      assert measurements.duration == duration
      assert measurements.size_bytes == size_bytes
      assert metadata.artifact_key == artifact_key

      :telemetry.detach("test-artifact-download")
    end

    test "emits DLQ enqueue event" do
      test_pid = self()

      :telemetry.attach(
        "test-dlq-enqueue",
        [:forge, :dlq, :enqueue],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      sample_id = "sample-123"
      stage = "MyStage"
      error = "Max retries exceeded"

      Telemetry.dlq_enqueue(sample_id, stage, error)

      assert_receive {:telemetry_event, [:forge, :dlq, :enqueue], measurements, metadata}
      assert measurements == %{}
      assert metadata.sample_id == sample_id
      assert metadata.stage == stage
      assert metadata.error == error

      :telemetry.detach("test-dlq-enqueue")
    end
  end

  describe "span/3" do
    test "executes function and emits start/stop events" do
      test_pid = self()

      :telemetry.attach_many(
        "test-span",
        [
          [:forge, :test, :start],
          [:forge, :test, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      result =
        Telemetry.span([:forge, :test], %{id: "123"}, fn ->
          # Simulate some work with a simple operation instead of sleep
          _dummy = Enum.reduce(1..100, 0, fn x, acc -> acc + x end)
          {:ok, "result"}
        end)

      assert result == {:ok, "result"}

      assert_receive {:telemetry_event, [:forge, :test, :start], start_measurements,
                      start_metadata}

      assert is_integer(start_measurements.system_time)
      assert start_metadata.id == "123"

      assert_receive {:telemetry_event, [:forge, :test, :stop], stop_measurements, stop_metadata}
      assert is_integer(stop_measurements.duration)
      assert stop_measurements.duration > 0
      assert stop_metadata.id == "123"

      :telemetry.detach("test-span")
    end

    test "emits exception event on error" do
      test_pid = self()

      :telemetry.attach_many(
        "test-span-error",
        [
          [:forge, :test, :start],
          [:forge, :test, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      assert_raise RuntimeError, "test error", fn ->
        Telemetry.span([:forge, :test], %{id: "123"}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:forge, :test, :start], _, _}

      assert_receive {:telemetry_event, [:forge, :test, :exception], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.id == "123"
      assert metadata.kind == :error
      assert metadata.reason == %RuntimeError{message: "test error"}

      :telemetry.detach("test-span-error")
    end
  end
end
