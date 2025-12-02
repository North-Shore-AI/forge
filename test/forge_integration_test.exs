defmodule ForgeIntegrationTest do
  use ExUnit.Case, async: false

  alias Forge.{Sample, Runner}

  # Define a realistic pipeline scenario
  defmodule DataPipeline do
    use Forge.Pipeline

    # Stages
    defmodule Normalize do
      @behaviour Forge.Stage

      def process(sample) do
        value = sample.data.raw_value / 100.0
        data = Map.put(sample.data, :normalized, value)
        {:ok, %{sample | data: data}}
      end
    end

    defmodule Validate do
      @behaviour Forge.Stage

      def process(sample) do
        if sample.data.normalized >= 0 and sample.data.normalized <= 10 do
          {:ok, sample}
        else
          {:skip, :out_of_range}
        end
      end
    end

    defmodule Enrich do
      @behaviour Forge.Stage

      def process(sample) do
        category =
          cond do
            sample.data.normalized < 3 -> :low
            sample.data.normalized < 7 -> :medium
            true -> :high
          end

        data = Map.put(sample.data, :category, category)
        {:ok, %{sample | data: data}}
      end
    end

    # Measurements
    defmodule Statistics do
      @behaviour Forge.Measurement

      def compute(samples) do
        values = Enum.map(samples, & &1.data.normalized)

        stats = %{
          count: length(values),
          mean: Enum.sum(values) / length(values),
          min: Enum.min(values),
          max: Enum.max(values)
        }

        {:ok, stats}
      end
    end

    defmodule CategoryDistribution do
      @behaviour Forge.Measurement

      def compute(samples) do
        distribution =
          samples
          |> Enum.group_by(& &1.data.category)
          |> Enum.map(fn {cat, samples} -> {cat, length(samples)} end)
          |> Map.new()

        {:ok, %{distribution: distribution}}
      end
    end

    # Pipeline definition
    pipeline :data_processing do
      source(Forge.Source.Generator,
        count: 100,
        generator: fn i ->
          %{
            raw_value: :rand.uniform(1000),
            timestamp: i,
            metadata: %{batch: div(i, 10)}
          }
        end
      )

      stage(Normalize)
      stage(Validate)
      stage(Enrich)

      measurement(Statistics)
      measurement(CategoryDistribution)

      storage(Forge.Storage.ETS, table: :integration_test_samples)
    end
  end

  setup do
    # Cleanup any existing table
    table = :integration_test_samples

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    on_exit(fn ->
      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end)

    :ok
  end

  test "complete pipeline execution with all features" do
    {:ok, runner} =
      Runner.start_link(
        pipeline_module: DataPipeline,
        pipeline_name: :data_processing
      )

    # Run pipeline
    samples = Runner.run(runner)

    # Verify samples were processed
    assert length(samples) > 0
    assert length(samples) <= 100

    # All returned samples should be ready and measured
    assert Enum.all?(samples, &Sample.ready?/1)
    assert Enum.all?(samples, &Sample.measured?/1)

    # All samples should have normalized values in valid range
    assert Enum.all?(samples, fn s ->
             s.data.normalized >= 0 and s.data.normalized <= 10
           end)

    # All samples should have category
    assert Enum.all?(samples, fn s -> s.data.category in [:low, :medium, :high] end)

    # Verify measurements are present
    sample = hd(samples)
    assert is_number(sample.measurements.mean)
    assert is_number(sample.measurements.min)
    assert is_number(sample.measurements.max)
    assert sample.measurements.count == length(samples)
    assert is_map(sample.measurements.distribution)

    # Verify distribution makes sense
    dist = sample.measurements.distribution
    total_in_dist = Enum.sum(Map.values(dist))
    assert total_in_dist == length(samples)

    # Verify samples were stored
    {:ok, storage_state} = Forge.Storage.ETS.init(table: :integration_test_samples)
    {:ok, stored, _state} = Forge.Storage.ETS.list([], storage_state)
    assert length(stored) == length(samples)

    # Verify we can retrieve individual samples
    first_sample = hd(samples)
    {:ok, retrieved, _state} = Forge.Storage.ETS.retrieve(first_sample.id, storage_state)
    assert retrieved.id == first_sample.id

    # Get status
    status = Runner.status(runner)
    assert status.samples_processed == length(samples)
    assert status.samples_skipped >= 0

    Runner.stop(runner)
  end

  test "high-level Forge API" do
    {:ok, runner} =
      Forge.start_pipeline(
        pipeline_module: DataPipeline,
        pipeline_name: :data_processing
      )

    samples = Forge.run_pipeline(runner)
    assert is_list(samples)
    assert length(samples) > 0

    status = Forge.pipeline_status(runner)
    assert status.status == :idle
    assert status.samples_processed > 0

    :ok = Forge.stop_pipeline(runner)
  end

  test "sample lifecycle through complete pipeline" do
    defmodule LifecyclePipeline do
      use Forge.Pipeline

      pipeline :lifecycle do
        source(Forge.Source.Static, data: [%{value: 1}])

        stage(DataPipeline.Normalize)
        measurement(DataPipeline.Statistics)
        storage(Forge.Storage.ETS, table: :lifecycle_test)
      end
    end

    # Cleanup
    if :ets.whereis(:lifecycle_test) != :undefined do
      :ets.delete(:lifecycle_test)
    end

    {:ok, runner} =
      Runner.start_link(
        pipeline_module: LifecyclePipeline,
        pipeline_name: :lifecycle
      )

    samples = Runner.run(runner)
    sample = hd(samples)

    # Verify lifecycle progression
    # Should be: pending -> measured -> ready
    assert sample.status == :ready
    assert sample.measured_at != nil
    assert sample.created_at != nil

    Runner.stop(runner)
    :ets.delete(:lifecycle_test)
  end

  test "handling large batch of samples" do
    defmodule LargeBatchPipeline do
      use Forge.Pipeline

      pipeline :large_batch do
        source(Forge.Source.Generator,
          count: 10_000,
          batch_size: 1000,
          generator: fn i -> %{index: i, value: rem(i, 100)} end
        )

        stage(DataPipeline.Normalize)

        storage(Forge.Storage.ETS, table: :large_batch_test)
      end
    end

    # Cleanup
    if :ets.whereis(:large_batch_test) != :undefined do
      :ets.delete(:large_batch_test)
    end

    {:ok, runner} =
      Runner.start_link(
        pipeline_module: LargeBatchPipeline,
        pipeline_name: :large_batch
      )

    {time, samples} = :timer.tc(fn -> Runner.run(runner) end)

    # Should process all samples
    assert length(samples) == 10_000

    # Should be reasonably fast (less than 5 seconds)
    assert time < 5_000_000

    status = Runner.status(runner)
    assert status.samples_processed == 10_000

    Runner.stop(runner)
    :ets.delete(:large_batch_test)
  end

  test "error handling and skipped samples" do
    defmodule ErrorHandlingPipeline do
      use Forge.Pipeline

      defmodule SkipHalf do
        @behaviour Forge.Stage

        def process(sample) do
          if rem(sample.data.value, 2) == 0 do
            {:ok, sample}
          else
            {:skip, :odd_value}
          end
        end
      end

      pipeline :error_handling do
        source(Forge.Source.Generator,
          count: 20,
          generator: fn i -> %{value: i} end
        )

        stage(SkipHalf)
      end
    end

    {:ok, runner} =
      Runner.start_link(
        pipeline_module: ErrorHandlingPipeline,
        pipeline_name: :error_handling
      )

    samples = Runner.run(runner)
    status = Runner.status(runner)

    # Half should be processed, half skipped
    assert status.samples_processed == 10
    assert status.samples_skipped == 10
    assert length(samples) == 10

    # All returned samples should have even values
    assert Enum.all?(samples, fn s -> rem(s.data.value, 2) == 0 end)

    Runner.stop(runner)
  end
end
