defmodule Forge.Measurement.OrchestratorTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Forge.Repo
  alias Forge.Measurement.Orchestrator
  alias Forge.Schema.{MeasurementRecord, Sample, Pipeline}

  setup do
    # Use sandbox for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create test pipeline
    manifest = %{stages: [], measurements: []}
    manifest_hash = :crypto.hash(:sha256, :erlang.term_to_binary(manifest)) |> Base.encode16()

    {:ok, pipeline} =
      %Pipeline{}
      |> Pipeline.changeset(%{
        name: "test_pipeline",
        manifest: manifest,
        manifest_hash: manifest_hash,
        status: "pending"
      })
      |> Repo.insert()

    # Create test samples
    samples =
      Enum.map(1..5, fn i ->
        {:ok, sample} =
          %Sample{}
          |> Sample.changeset(%{
            pipeline_id: pipeline.id,
            status: "pending",
            data: %{text: "Sample #{i}", value: i}
          })
          |> Repo.insert()

        sample
      end)

    {:ok, pipeline: pipeline, samples: samples}
  end

  describe "measure_sample/3" do
    test "computes and stores new measurement", %{samples: [sample | _]} do
      measurement_module = TestMeasurement.Simple

      {:ok, :computed, value} =
        Orchestrator.measure_sample(sample.id, measurement_module, [])

      assert value == %{length: 8}

      # Verify stored in database
      measurement =
        Repo.one(
          from(m in MeasurementRecord,
            where: m.sample_id == ^sample.id and m.measurement_key == ^measurement_module.key()
          )
        )

      assert measurement != nil
      assert measurement.value == %{"length" => 8}
      assert measurement.measurement_version == 1
    end

    test "returns cached measurement on second call", %{samples: [sample | _]} do
      measurement_module = TestMeasurement.Simple

      # First call - compute
      {:ok, :computed, _} = Orchestrator.measure_sample(sample.id, measurement_module, [])

      # Second call - cached (returns from DB with string keys)
      {:ok, :cached, value} = Orchestrator.measure_sample(sample.id, measurement_module, [])

      assert value == %{"length" => 8}
    end

    test "computes new version when version changes", %{samples: [sample | _]} do
      # Compute version 1
      {:ok, :computed, _} = Orchestrator.measure_sample(sample.id, TestMeasurement.Simple, [])

      # Simulate version change
      {:ok, :computed, value} =
        Orchestrator.measure_sample(sample.id, TestMeasurement.SimpleV2, [])

      assert value == %{length: 8, version: 2}

      # Verify both versions exist
      measurements =
        Repo.all(
          from(m in MeasurementRecord,
            where:
              m.sample_id == ^sample.id and m.measurement_key == ^TestMeasurement.Simple.key()
          )
        )

      assert length(measurements) == 2
    end

    test "handles measurement computation errors", %{samples: [sample | _]} do
      {:error, reason} =
        Orchestrator.measure_sample(sample.id, TestMeasurement.Error, [])

      assert reason == :computation_failed
    end
  end

  describe "measure_batch/3" do
    test "computes measurements for multiple samples", %{samples: samples} do
      sample_ids = Enum.map(samples, & &1.id)

      results = Orchestrator.measure_batch(sample_ids, TestMeasurement.Simple, [])

      assert length(results) == 5

      Enum.each(results, fn result ->
        assert {:ok, :computed, _value} = result
      end)
    end

    test "respects batch_size option for batch-capable measurements", %{samples: samples} do
      sample_ids = Enum.map(samples, & &1.id)

      results =
        Orchestrator.measure_batch(sample_ids, TestMeasurement.BatchCapable, batch_size: 2)

      # All should succeed
      assert length(results) == 5

      Enum.each(results, fn result ->
        assert {:ok, :computed, _value} = result
      end)
    end

    test "handles mix of cached and new measurements", %{samples: samples} do
      sample_ids = Enum.map(samples, & &1.id)

      # Pre-compute first two
      Orchestrator.measure_sample(Enum.at(sample_ids, 0), TestMeasurement.Simple, [])
      Orchestrator.measure_sample(Enum.at(sample_ids, 1), TestMeasurement.Simple, [])

      results = Orchestrator.measure_batch(sample_ids, TestMeasurement.Simple, [])

      cached = Enum.count(results, fn {_, status, _} -> status == :cached end)
      computed = Enum.count(results, fn {_, status, _} -> status == :computed end)

      assert cached == 2
      assert computed == 3
    end
  end

  describe "measure_async/3" do
    test "executes measurements asynchronously", %{samples: samples} do
      sample_ids = Enum.map(samples, & &1.id)

      task = Orchestrator.measure_async(sample_ids, TestMeasurement.Simple, [])

      results = Task.await(task, 5000)

      assert length(results) == 5

      Enum.each(results, fn result ->
        assert {:ok, _, _} = result
      end)
    end

    test "handles async computation errors", %{samples: [sample | _]} do
      task = Orchestrator.measure_async([sample.id], TestMeasurement.Error, [])

      results = Task.await(task, 5000)

      assert [{:error, :computation_failed}] = results
    end
  end

  describe "measure_with_dependencies/3" do
    test "resolves and executes dependencies in order", %{samples: [sample | _]} do
      # TestMeasurement.WithDep depends on TestMeasurement.Simple
      {:ok, status, value} =
        Orchestrator.measure_with_dependencies(sample.id, TestMeasurement.WithDep, [])

      # Should be computed (first time)
      assert status in [:computed, :cached]
      assert value == %{computed_from_dep: 8} or value == %{"computed_from_dep" => 8}

      # Verify dependency was computed
      dep_measurement =
        Repo.one(
          from(m in MeasurementRecord,
            where:
              m.sample_id == ^sample.id and m.measurement_key == ^TestMeasurement.Simple.key()
          )
        )

      assert dep_measurement != nil
    end

    test "uses cached dependencies", %{samples: [sample | _]} do
      # Pre-compute dependency
      {:ok, :computed, _} = Orchestrator.measure_sample(sample.id, TestMeasurement.Simple, [])

      # Compute dependent measurement - dependency will be cached
      {:ok, status, value} =
        Orchestrator.measure_with_dependencies(sample.id, TestMeasurement.WithDep, [])

      assert status in [:computed, :cached]
      assert value == %{computed_from_dep: 8} or value == %{"computed_from_dep" => 8}
    end

    test "handles circular dependencies", %{samples: [sample | _]} do
      {:error, reason} =
        Orchestrator.measure_with_dependencies(sample.id, TestMeasurement.Circular, [])

      assert reason == :circular_dependency
    end
  end

  describe "get_measurement/3" do
    test "retrieves latest version by default", %{samples: [sample | _]} do
      Orchestrator.measure_sample(sample.id, TestMeasurement.Simple, [])

      {:ok, measurement} =
        Orchestrator.get_measurement(sample.id, TestMeasurement.Simple.key())

      assert measurement.value == %{"length" => 8}
      assert measurement.measurement_version == 1
    end

    test "retrieves specific version", %{samples: [sample | _]} do
      # Compute v1
      Orchestrator.measure_sample(sample.id, TestMeasurement.Simple, [])

      # Compute v2
      Orchestrator.measure_sample(sample.id, TestMeasurement.SimpleV2, [])

      {:ok, measurement} =
        Orchestrator.get_measurement(sample.id, TestMeasurement.Simple.key(), version: 1)

      assert measurement.measurement_version == 1
    end

    test "returns error when measurement not found", %{samples: [sample | _]} do
      {:error, :not_found} =
        Orchestrator.get_measurement(sample.id, "nonexistent:key")
    end
  end

  describe "telemetry integration" do
    test "emits measurement events", %{samples: [sample | _]} do
      # Attach test handler
      handler_id = "test-measurement-handler-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:forge, :measurement, :stop],
        fn _event, measurements, metadata, acc ->
          send(self(), {:telemetry_event, measurements, metadata})
          acc
        end,
        nil
      )

      Orchestrator.measure_sample(sample.id, TestMeasurement.Simple, [])

      assert_receive {:telemetry_event, %{duration: duration}, metadata}, 1000

      assert duration > 0
      assert metadata.sample_id == sample.id
      assert metadata.outcome == :computed

      :telemetry.detach(handler_id)
    end
  end
end

# Test measurement implementations
defmodule TestMeasurement.Simple do
  @behaviour Forge.Measurement

  def key, do: "test:simple:#{config_hash()}"
  def version, do: 1

  def compute([%{data: %{"text" => text}} | _]) do
    {:ok, %{length: String.length(text)}}
  end

  def compute(_), do: {:error, :invalid_data}

  defp config_hash do
    :crypto.hash(:sha256, :erlang.term_to_binary(%{}))
    |> Base.encode16()
    |> String.slice(0..7)
  end
end

defmodule TestMeasurement.SimpleV2 do
  @behaviour Forge.Measurement

  def key, do: TestMeasurement.Simple.key()
  def version, do: 2

  def compute([%{data: %{"text" => text}} | _]) do
    {:ok, %{length: String.length(text), version: 2}}
  end

  def compute(_), do: {:error, :invalid_data}
end

defmodule TestMeasurement.Error do
  @behaviour Forge.Measurement

  def key, do: "test:error"
  def version, do: 1

  def compute(_), do: {:error, :computation_failed}
end

defmodule TestMeasurement.BatchCapable do
  @behaviour Forge.Measurement

  def key, do: "test:batch"
  def version, do: 1

  def batch_capable?, do: true
  def batch_size, do: 3

  def compute_batch(samples) do
    Enum.map(samples, fn sample ->
      %{"text" => text} = sample.data
      {sample.id, %{length: String.length(text), batched: true}}
    end)
  end

  def compute([sample | _]) do
    results = compute_batch([sample])
    {:ok, elem(hd(results), 1)}
  end
end

defmodule TestMeasurement.WithDep do
  @behaviour Forge.Measurement

  def key, do: "test:withdep"
  def version, do: 1

  def dependencies, do: [TestMeasurement.Simple]

  def compute([%{id: _sample_id} | _]) do
    # In real implementation, would fetch dependency value
    {:ok, %{computed_from_dep: 8}}
  end
end

defmodule TestMeasurement.Circular do
  @behaviour Forge.Measurement

  def key, do: "test:circular"
  def version, do: 1

  def dependencies, do: [__MODULE__]

  def compute(_), do: {:ok, %{}}
end
