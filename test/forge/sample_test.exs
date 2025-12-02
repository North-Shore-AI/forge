defmodule Forge.SampleTest do
  use ExUnit.Case, async: true

  alias Forge.Sample

  describe "new/1" do
    test "creates a sample with required fields" do
      sample =
        Sample.new(
          id: "test-123",
          pipeline: :test_pipeline,
          data: %{value: 42}
        )

      assert sample.id == "test-123"
      assert sample.pipeline == :test_pipeline
      assert sample.data == %{value: 42}
      assert sample.status == :pending
      assert sample.measurements == %{}
      assert %DateTime{} = sample.created_at
      assert sample.measured_at == nil
    end

    test "allows custom status" do
      sample =
        Sample.new(
          id: "test-123",
          pipeline: :test,
          data: %{},
          status: :ready
        )

      assert sample.status == :ready
    end

    test "allows custom measurements" do
      sample =
        Sample.new(
          id: "test-123",
          pipeline: :test,
          data: %{},
          measurements: %{mean: 42.0}
        )

      assert sample.measurements == %{mean: 42.0}
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Sample.new(pipeline: :test, data: %{})
      end
    end
  end

  describe "status predicates" do
    test "pending?/1" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{}, status: :pending)
      assert Sample.pending?(sample)
      refute Sample.measured?(sample)
    end

    test "measured?/1" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{}, status: :measured)
      assert Sample.measured?(sample)
      refute Sample.pending?(sample)
    end

    test "ready?/1" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{}, status: :ready)
      assert Sample.ready?(sample)
    end

    test "labeled?/1" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{}, status: :labeled)
      assert Sample.labeled?(sample)
    end

    test "skipped?/1" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{}, status: :skipped)
      assert Sample.skipped?(sample)
    end
  end

  describe "mark_* functions" do
    setup do
      sample = Sample.new(id: "1", pipeline: :test, data: %{})
      {:ok, sample: sample}
    end

    test "mark_measured/1 sets status and timestamp", %{sample: sample} do
      measured = Sample.mark_measured(sample)

      assert measured.status == :measured
      assert %DateTime{} = measured.measured_at
    end

    test "mark_ready/1 sets status", %{sample: sample} do
      ready = Sample.mark_ready(sample)
      assert ready.status == :ready
    end

    test "mark_labeled/1 sets status", %{sample: sample} do
      labeled = Sample.mark_labeled(sample)
      assert labeled.status == :labeled
    end

    test "mark_skipped/1 sets status", %{sample: sample} do
      skipped = Sample.mark_skipped(sample)
      assert skipped.status == :skipped
    end
  end

  describe "add_measurements/2" do
    test "adds measurements to empty map" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{})
      updated = Sample.add_measurements(sample, %{mean: 42.0, count: 10})

      assert updated.measurements == %{mean: 42.0, count: 10}
    end

    test "merges with existing measurements" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{}, measurements: %{count: 5})
      updated = Sample.add_measurements(sample, %{mean: 42.0})

      assert updated.measurements == %{count: 5, mean: 42.0}
    end
  end

  describe "update_data/2" do
    test "replaces data completely" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{old: "value"})
      updated = Sample.update_data(sample, %{new: "value"})

      assert updated.data == %{new: "value"}
    end
  end

  describe "merge_data/2" do
    test "merges data maps" do
      sample = Sample.new(id: "1", pipeline: :test, data: %{a: 1, b: 2})
      updated = Sample.merge_data(sample, %{b: 3, c: 4})

      assert updated.data == %{a: 1, b: 3, c: 4}
    end
  end
end
