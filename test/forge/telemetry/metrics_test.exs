defmodule Forge.Telemetry.MetricsTest do
  use ExUnit.Case, async: true

  alias Forge.Telemetry.Metrics

  describe "metrics/0" do
    test "returns a list of metric definitions" do
      metrics = Metrics.metrics()

      assert is_list(metrics)
      assert length(metrics) > 0

      # Check that all metrics have required fields
      Enum.each(metrics, fn metric ->
        assert is_map(metric)
        assert Map.has_key?(metric, :type)
        assert Map.has_key?(metric, :name)
        assert Map.has_key?(metric, :event_name)
        assert Map.has_key?(metric, :description)
        assert metric.type in [:counter, :distribution]
      end)
    end

    test "counter metrics have correct structure" do
      counters = Metrics.counters()

      Enum.each(counters, fn metric ->
        assert metric.type == :counter
        assert is_list(metric.name)
        assert is_list(metric.event_name)
        assert is_list(metric.tags)
      end)
    end

    test "distribution metrics have correct structure" do
      distributions = Metrics.distributions()

      Enum.each(distributions, fn metric ->
        assert metric.type == :distribution
        assert is_list(metric.name)
        assert is_list(metric.event_name)
        assert Map.has_key?(metric, :unit)
        assert Map.has_key?(metric, :buckets)
        assert is_list(metric.buckets)
      end)
    end
  end

  describe "counters/0" do
    test "returns only counter metrics" do
      counters = Metrics.counters()

      assert length(counters) > 0
      assert Enum.all?(counters, fn m -> m.type == :counter end)
    end
  end

  describe "distributions/0" do
    test "returns only distribution metrics" do
      distributions = Metrics.distributions()

      assert length(distributions) > 0
      assert Enum.all?(distributions, fn m -> m.type == :distribution end)
    end
  end

  describe "category/1" do
    test "returns pipeline metrics" do
      pipeline_metrics = Metrics.category(:pipeline)

      assert length(pipeline_metrics) > 0

      Enum.each(pipeline_metrics, fn metric ->
        assert [:forge, :pipeline | _] = metric.event_name
      end)
    end

    test "returns stage metrics" do
      stage_metrics = Metrics.category(:stage)

      assert length(stage_metrics) > 0

      Enum.each(stage_metrics, fn metric ->
        assert [:forge, :stage | _] = metric.event_name
      end)
    end

    test "returns measurement metrics" do
      measurement_metrics = Metrics.category(:measurement)

      assert length(measurement_metrics) > 0

      Enum.each(measurement_metrics, fn metric ->
        assert [:forge, :measurement | _] = metric.event_name
      end)
    end

    test "returns storage metrics" do
      storage_metrics = Metrics.category(:storage)

      assert length(storage_metrics) > 0

      Enum.each(storage_metrics, fn metric ->
        assert [:forge, :storage | _] = metric.event_name
      end)
    end

    test "returns DLQ metrics" do
      dlq_metrics = Metrics.category(:dlq)

      assert length(dlq_metrics) > 0

      Enum.each(dlq_metrics, fn metric ->
        assert [:forge, :dlq | _] = metric.event_name
      end)
    end
  end

  describe "metric definitions" do
    test "pipeline completed counter exists" do
      metric =
        Metrics.metrics()
        |> Enum.find(fn m -> m.name == [:forge, :pipeline, :completed] end)

      assert metric
      assert metric.type == :counter
      assert metric.event_name == [:forge, :pipeline, :stop]
      assert :outcome in metric.tags
    end

    test "stage latency distribution exists" do
      metric =
        Metrics.metrics()
        |> Enum.find(fn m -> m.name == [:forge, :stage, :latency] end)

      assert metric
      assert metric.type == :distribution
      assert metric.event_name == [:forge, :stage, :stop]
      assert metric.unit == {:native, :millisecond}
      assert is_list(metric.buckets)
    end

    test "storage sample write metrics exist" do
      duration_metric =
        Metrics.metrics()
        |> Enum.find(fn m -> m.name == [:forge, :storage, :sample_write_duration] end)

      assert duration_metric
      assert duration_metric.type == :distribution

      size_metric =
        Metrics.metrics()
        |> Enum.find(fn m -> m.name == [:forge, :storage, :sample_write_size] end)

      assert size_metric
      assert size_metric.type == :distribution
      assert size_metric.unit == :byte
    end

    test "DLQ enqueued counter exists" do
      metric =
        Metrics.metrics()
        |> Enum.find(fn m -> m.name == [:forge, :dlq, :enqueued] end)

      assert metric
      assert metric.type == :counter
      assert metric.event_name == [:forge, :dlq, :enqueue]
    end
  end
end
