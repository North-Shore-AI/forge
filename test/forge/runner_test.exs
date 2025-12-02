defmodule Forge.RunnerTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.{Runner, Sample}

  import Supertester.Assertions

  defmodule TestPipelines do
    use Forge.Pipeline

    pipeline :simple do
      source(Forge.Source.Static, data: [%{value: 1}, %{value: 2}, %{value: 3}])
    end

    pipeline :with_stages do
      source(Forge.Source.Static, data: [%{value: 1}, %{value: 2}, %{value: 3}])
      stage(TestStages.SimpleStage)
    end

    pipeline :with_filter do
      source(Forge.Source.Static,
        data: [%{value: 1}, %{value: 5}, %{value: 10}, %{value: 15}]
      )

      stage(TestStages.FilterStage)
    end

    pipeline :with_measurements do
      source(Forge.Source.Static, data: [%{value: 10}, %{value: 20}, %{value: 30}])
      measurement(TestStages.SyncMeasurement)
    end

    pipeline :with_async_measurement do
      source(Forge.Source.Static, data: [%{value: 1}])
      measurement(TestStages.AsyncMeasurement)
    end

    pipeline :with_storage do
      source(Forge.Source.Static, data: [%{value: 42}])
      storage(Forge.Storage.ETS, table: :runner_test_storage)
    end

    pipeline :complete_pipeline do
      source(Forge.Source.Generator, count: 5, generator: fn i -> %{value: i + 1} end)
      stage(TestStages.SimpleStage)
      measurement(TestStages.SyncMeasurement)
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

      assert_process_alive(pid)
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
      # Trap exits to handle the GenServer stopping with an error
      Process.flag(:trap_exit, true)

      result =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :non_existent
        )

      case result do
        {:error, {reason, _}} ->
          assert reason == :error

        {:ok, pid} ->
          # Wait for the EXIT message
          assert_receive {:EXIT, ^pid, {:error, reason}}, 1000
          assert reason =~ "Pipeline non_existent not found"
      end
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
      assert Enum.all?(samples, fn s -> s.measured_at != nil end)

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

      assert Enum.all?(samples, fn s -> s.measured_at != nil end)

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
      assert hd(samples).status == :ready

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

      # Clean up table if it still exists
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
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
      assert Enum.all?(samples, fn s -> s.measured_at != nil end)

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

      # Clean up table if it still exists
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
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
      table = :runner_test_storage

      {:ok, pid} =
        Runner.start_link(
          pipeline_module: TestPipelines,
          pipeline_name: :with_storage
        )

      Runner.run(pid)

      # Table exists while runner is alive
      assert :ets.whereis(table) != :undefined

      Runner.stop(pid)

      # Ensure the runner finishes terminating before asserting cleanup
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
      assert_process_dead(pid)

      # Table should be deleted after cleanup
      assert :ets.whereis(table) == :undefined
    end
  end
end
