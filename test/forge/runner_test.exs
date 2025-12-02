defmodule Forge.RunnerTest do
  use ExUnit.Case, async: true

  alias Forge.{Runner, Sample}

  # Test helpers
  defmodule SimpleStage do
    @behaviour Forge.Stage

    def process(sample) do
      data = Map.update!(sample.data, :value, &(&1 * 2))
      {:ok, %{sample | data: data}}
    end
  end

  defmodule FilterStage do
    @behaviour Forge.Stage

    def process(sample) do
      if sample.data.value > 5 do
        {:ok, sample}
      else
        {:skip, :too_small}
      end
    end
  end

  defmodule ErrorStage do
    @behaviour Forge.Stage

    def process(_sample) do
      {:error, :intentional_error}
    end
  end

  defmodule SyncMeasurement do
    @behaviour Forge.Measurement

    def compute(samples) do
      count = length(samples)
      sum = Enum.reduce(samples, 0, fn s, acc -> acc + s.data.value end)
      {:ok, %{count: count, sum: sum}}
    end
  end

  defmodule AsyncMeasurement do
    @behaviour Forge.Measurement

    def compute(samples) do
      {:ok, %{async_count: length(samples)}}
    end

    def async?(), do: true
  end

  defmodule TestPipelines do
    use Forge.Pipeline

    pipeline :simple do
      source(Forge.Source.Static, data: [%{value: 1}, %{value: 2}, %{value: 3}])
    end

    pipeline :with_stages do
      source(Forge.Source.Static, data: [%{value: 1}, %{value: 2}, %{value: 3}])
      stage(SimpleStage)
    end

    pipeline :with_filter do
      source(Forge.Source.Static,
        data: [%{value: 1}, %{value: 5}, %{value: 10}, %{value: 15}]
      )

      stage(FilterStage)
    end

    pipeline :with_measurements do
      source(Forge.Source.Static, data: [%{value: 10}, %{value: 20}, %{value: 30}])
      measurement(SyncMeasurement)
    end

    pipeline :with_async_measurement do
      source(Forge.Source.Static, data: [%{value: 1}])
      measurement(AsyncMeasurement)
    end

    pipeline :with_storage do
      source(Forge.Source.Static, data: [%{value: 42}])
      storage(Forge.Storage.ETS, table: :runner_test_storage)
    end

    pipeline :complete_pipeline do
      source(Forge.Source.Generator, count: 5, generator: fn i -> %{value: i + 1} end)
      stage(SimpleStage)
      measurement(SyncMeasurement)
      storage(Forge.Storage.ETS, table: :complete_test_storage)
    end
  end

  describe "start_link/1" do
    test "starts runner for valid pipeline" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :simple
        )

      assert Process.alive?(pid)
      Runner.stop(pid)
    end

    test "can start with custom name" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :simple,
          name: :test_runner
        )

      assert Process.whereis(:test_runner) == pid
      Runner.stop(pid)
    end

    test "fails for non-existent pipeline" do
      {:error, {reason, _}} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :non_existent
        )

      assert reason == :error
    end
  end

  describe "run/1" do
    test "runs simple pipeline and returns samples" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :simple
        )

      samples = Runner.run(pid)

      assert length(samples) == 3
      assert Enum.all?(samples, &Sample.ready?/1)
      assert Enum.all?(samples, &Sample.measured?/1)

      Runner.stop(pid)
    end

    test "applies stages to samples" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_stages
        )

      samples = Runner.run(pid)

      # SimpleStage doubles the value
      values = Enum.map(samples, & &1.data.value)
      assert values == [2, 4, 6]

      Runner.stop(pid)
    end

    test "filters samples based on stage logic" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_filter
        )

      samples = Runner.run(pid)

      # Only values > 5 should pass
      assert length(samples) == 2
      values = Enum.map(samples, & &1.data.value)
      assert 10 in values
      assert 15 in values

      Runner.stop(pid)
    end

    test "computes synchronous measurements" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_measurements
        )

      samples = Runner.run(pid)

      assert Enum.all?(samples, &Sample.measured?/1)

      # All samples should have same measurements (aggregate)
      sample = hd(samples)
      assert sample.measurements.count == 3
      assert sample.measurements.sum == 60

      Runner.stop(pid)
    end

    test "handles async measurements without blocking" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_async_measurement
        )

      samples = Runner.run(pid)

      # Async measurements don't block, so they won't be in sample.measurements
      assert length(samples) == 1
      assert hd(samples).status == :measured

      Runner.stop(pid)
    end

    test "stores samples when storage configured" do
      table = :runner_test_storage

      # Clean up table if it exists
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)

      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_storage
        )

      samples = Runner.run(pid)

      # Verify samples were stored
      assert length(samples) == 1

      # Check ETS table
      stored = :ets.tab2list(table)
      assert length(stored) == 1

      Runner.stop(pid)
      :ets.delete(table)
    end

    test "runs complete pipeline end-to-end" do
      table = :complete_test_storage

      # Clean up table if it exists
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)

      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :complete_pipeline
        )

      samples = Runner.run(pid)

      # Verify all aspects
      assert length(samples) == 5
      assert Enum.all?(samples, &Sample.ready?/1)
      assert Enum.all?(samples, &Sample.measured?/1)

      # Values should be doubled by SimpleStage
      values = Enum.map(samples, & &1.data.value)
      assert values == [2, 4, 6, 8, 10]

      # Measurements should be present
      assert hd(samples).measurements.count == 5
      assert hd(samples).measurements.sum == 30

      # Samples should be stored
      stored = :ets.tab2list(table)
      assert length(stored) == 5

      Runner.stop(pid)
      :ets.delete(table)
    end
  end

  describe "status/1" do
    test "returns idle status before running" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :simple
        )

      status = Runner.status(pid)

      assert status.status == :idle
      assert status.samples_processed == 0
      assert status.samples_skipped == 0
      assert status.pipeline == :simple

      Runner.stop(pid)
    end

    test "returns updated status after running" do
      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_filter
        )

      _samples = Runner.run(pid)
      status = Runner.status(pid)

      assert status.status == :idle
      assert status.samples_processed == 2
      assert status.samples_skipped == 2
      assert status.run_id != nil

      Runner.stop(pid)
    end
  end

  describe "lifecycle" do
    test "cleans up resources on stop" do
      table = :lifecycle_test_storage

      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_storage
        )

      Runner.run(pid)

      # Table exists while runner is alive
      assert :ets.whereis(table) != :undefined

      Runner.stop(pid)

      # Give it a moment to clean up
      Process.sleep(10)

      # Table should be deleted after cleanup
      assert :ets.whereis(table) == :undefined
    end
  end
end
