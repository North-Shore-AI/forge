defmodule Forge.Runner.StreamingTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureLog

  alias Forge.Runner.Streaming
  alias Forge.Sample

  # Mock source for testing
  defmodule MockSource do
    @behaviour Forge.Source

    @impl true
    def init(opts) do
      samples = Keyword.get(opts, :samples, [])
      {:ok, %{samples: samples, index: 0}}
    end

    @impl true
    def fetch(%{samples: samples, index: index}) when index >= length(samples) do
      {:done, %{samples: samples, index: index}}
    end

    @impl true
    def fetch(%{samples: samples, index: index}) do
      batch_size = 2
      batch = Enum.slice(samples, index, batch_size)
      {:ok, batch, %{samples: samples, index: index + batch_size}}
    end

    @impl true
    def cleanup(_state), do: :ok
  end

  # Mock sync stage
  defmodule MockSyncStage do
    @behaviour Forge.Stage

    @impl true
    def process(sample) do
      # Add processing marker
      updated = Sample.merge_data(sample, %{processed_by: :sync_stage})
      {:ok, updated}
    end
  end

  # Mock async stage
  defmodule MockAsyncStage do
    @behaviour Forge.Stage

    @impl true
    def process(sample) do
      # Simulate async work with a simple computation instead of sleep
      _dummy = Enum.reduce(1..1000, 0, fn x, acc -> acc + x end)
      updated = Sample.merge_data(sample, %{processed_by: :async_stage})
      {:ok, updated}
    end

    @impl true
    def async?, do: true

    @impl true
    def concurrency, do: 4
  end

  # Mock filter stage
  defmodule MockFilterStage do
    @behaviour Forge.Stage

    @impl true
    def process(sample) do
      if sample.data[:value] > 5 do
        {:ok, sample}
      else
        {:skip, :value_too_low}
      end
    end
  end

  # Mock measurement
  defmodule MockMeasurement do
    @behaviour Forge.Measurement

    @impl true
    def key, do: "test:mock_measurement"

    @impl true
    def version, do: 1

    @impl true
    def compute(samples) do
      # Simple measurement: count samples
      {:ok, %{sample_count: length(samples)}}
    end
  end

  describe "run/2" do
    test "returns a stream" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}, %{value: 2}]],
        stages: [],
        measurements: []
      }

      result = Streaming.run(pipeline)
      # Stream is a struct in Elixir 1.18, check it implements Enumerable
      assert match?(%Stream{}, result)
    end

    test "lazily processes samples" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}, %{value: 2}, %{value: 3}]],
        stages: [],
        measurements: []
      }

      stream = Streaming.run(pipeline)

      # Take only 2 samples (lazy evaluation)
      samples = stream |> Enum.take(2)

      assert length(samples) == 2
    end

    test "processes all samples when consumed" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}, %{value: 2}, %{value: 3}]],
        stages: [],
        measurements: []
      }

      samples = Streaming.run(pipeline) |> Enum.to_list()

      assert length(samples) == 3
      assert Enum.all?(samples, fn s -> s.status == :ready end)
    end
  end

  describe "stage processing" do
    test "applies sync stages sequentially" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}]],
        stages: [{MockSyncStage, []}],
        measurements: []
      }

      samples = Streaming.run(pipeline) |> Enum.to_list()

      assert length(samples) == 1
      sample = hd(samples)
      assert sample.data[:processed_by] == :sync_stage
    end

    test "applies async stages with concurrency" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}, %{value: 2}, %{value: 3}, %{value: 4}]],
        stages: [{MockAsyncStage, []}],
        measurements: []
      }

      # Test that async processing works by verifying all samples are processed
      samples = Streaming.run(pipeline, concurrency: 4) |> Enum.to_list()

      assert length(samples) == 4
      assert Enum.all?(samples, fn s -> s.data[:processed_by] == :async_stage end)
    end

    test "filters samples with skip result" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [
          samples: [%{value: 3}, %{value: 7}, %{value: 2}, %{value: 9}]
        ],
        stages: [{MockFilterStage, []}],
        measurements: []
      }

      samples = Streaming.run(pipeline) |> Enum.to_list()

      # Only samples with value > 5 should pass
      assert length(samples) == 2
      assert Enum.all?(samples, fn s -> s.data[:value] > 5 end)
    end

    test "chains multiple stages" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 10}]],
        stages: [
          {MockSyncStage, []},
          {MockAsyncStage, []}
        ],
        measurements: []
      }

      samples = Streaming.run(pipeline) |> Enum.to_list()

      assert length(samples) == 1
      sample = hd(samples)
      # Should have been processed by async stage (last one)
      assert sample.data[:processed_by] == :async_stage
    end
  end

  describe "measurements" do
    test "computes measurements on samples" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}]],
        stages: [],
        measurements: [{MockMeasurement, []}]
      }

      samples = Streaming.run(pipeline) |> Enum.to_list()

      assert length(samples) == 1
      sample = hd(samples)
      assert sample.status == :ready
      assert sample.measurements[:sample_count] == 1
    end
  end

  describe "backpressure" do
    test "respects max_concurrency setting" do
      # Create many samples to test concurrency limits
      many_samples = Enum.map(1..20, fn i -> %{value: i} end)

      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: many_samples],
        stages: [{MockAsyncStage, []}],
        measurements: []
      }

      # Run with limited concurrency
      samples = Streaming.run(pipeline, concurrency: 2) |> Enum.to_list()

      # All samples should be processed despite low concurrency
      assert length(samples) == 20
    end

    test "memory bounded to concurrency level" do
      # This is more of a conceptual test - in practice we'd monitor memory
      # Here we verify that the stream processes lazily
      large_dataset = Enum.map(1..1000, fn i -> %{value: i} end)

      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: large_dataset],
        stages: [],
        measurements: []
      }

      stream = Streaming.run(pipeline, concurrency: 10)

      # Take only first 10 - should not load all 1000 into memory
      first_10 = stream |> Enum.take(10)
      assert length(first_10) == 10
    end
  end

  describe "error handling" do
    defmodule FailingStage do
      @behaviour Forge.Stage

      @impl true
      def process(_sample) do
        {:error, :intentional_failure}
      end
    end

    test "filters out samples with stage errors" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}, %{value: 2}]],
        stages: [{FailingStage, []}],
        measurements: []
      }

      capture_log(fn ->
        samples = Streaming.run(pipeline) |> Enum.to_list()

        # Failed samples should be filtered out
        assert samples == []
      end)
    end

    defmodule CrashingStage do
      @behaviour Forge.Stage

      @impl true
      def process(_sample) do
        raise "Intentional crash"
      end
    end

    test "handles stage crashes gracefully" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: [%{value: 1}]],
        stages: [{CrashingStage, []}],
        measurements: []
      }

      # Should not crash the test - errors are logged and samples filtered
      capture_log(fn ->
        samples = Streaming.run(pipeline) |> Enum.to_list()
        assert samples == []
      end)
    end
  end

  describe "storage integration" do
    defmodule MockStorage do
      @behaviour Forge.Storage

      def init(_opts) do
        # Use test process to track stored samples
        {:ok, %{pid: self()}}
      end

      def store(samples, state) do
        send(state.pid, {:stored, length(samples)})
        {:ok, state}
      end

      def cleanup(_state), do: :ok
    end

    test "persists samples to storage in chunks" do
      pipeline = %{
        name: :test_pipeline,
        source_module: MockSource,
        source_opts: [samples: Enum.map(1..250, fn i -> %{value: i} end)],
        stages: [],
        measurements: []
      }

      # Run with storage
      _samples =
        Streaming.run(pipeline,
          storage: MockStorage,
          storage_opts: []
        )
        |> Enum.to_list()

      # Should have received storage messages (chunked in batches of 100)
      assert_receive {:stored, 100}
      assert_receive {:stored, 100}
      assert_receive {:stored, 50}
    end
  end
end
