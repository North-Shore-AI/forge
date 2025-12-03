defmodule Forge.Storage.PostgresTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureLog

  alias Forge.Storage.Postgres
  alias Forge.Sample
  alias Forge.Repo

  # Use Ecto sandbox for test isolation
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Forge.Repo)
    :ok
  end

  describe "init/1" do
    test "creates or fetches pipeline record" do
      {:ok, state} = Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{})

      assert state.pipeline_id != nil
      assert state.pipeline_name == :test_pipeline
    end

    test "reuses existing pipeline with same manifest" do
      {:ok, state1} =
        Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{version: 1})

      {:ok, state2} =
        Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{version: 1})

      assert state1.pipeline_id == state2.pipeline_id
    end

    test "creates new pipeline for different manifest" do
      {:ok, state1} =
        Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{version: 1})

      {:ok, state2} =
        Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{version: 2})

      assert state1.pipeline_id != state2.pipeline_id
    end
  end

  describe "store/2" do
    setup do
      {:ok, state} = Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{})
      %{state: state}
    end

    test "persists samples to database", %{state: state} do
      id1 = Ecto.UUID.generate()
      id2 = Ecto.UUID.generate()

      samples = [
        Sample.new(
          id: id1,
          pipeline: :test_pipeline,
          data: %{value: 42}
        ),
        Sample.new(
          id: id2,
          pipeline: :test_pipeline,
          data: %{value: 99}
        )
      ]

      {:ok, _new_state} = Postgres.store(samples, state)

      # Verify samples were stored
      stored = Repo.all(Forge.Schema.Sample)
      assert length(stored) == 2
      assert Enum.any?(stored, fn s -> s.id == id1 end)
      assert Enum.any?(stored, fn s -> s.id == id2 end)
    end

    test "stores sample measurements", %{state: state} do
      sample_id = Ecto.UUID.generate()

      sample =
        Sample.new(
          id: sample_id,
          pipeline: :test_pipeline,
          data: %{value: 42},
          measurements: %{accuracy: 0.95, f1_score: 0.88}
        )
        |> Sample.mark_measured()

      {:ok, _new_state} = Postgres.store([sample], state)

      # Verify measurements were stored
      measurements = Repo.all(Forge.Schema.MeasurementRecord)
      assert length(measurements) == 2
      assert Enum.any?(measurements, fn m -> m.measurement_key == "accuracy" end)
      assert Enum.any?(measurements, fn m -> m.measurement_key == "f1_score" end)
    end

    test "handles upserts on conflict", %{state: state} do
      sample_id = Ecto.UUID.generate()

      sample =
        Sample.new(
          id: sample_id,
          pipeline: :test_pipeline,
          data: %{value: 42}
        )

      # Store once
      {:ok, _} = Postgres.store([sample], state)

      # Store again with updated data
      updated_sample = Sample.update_data(sample, %{value: 99})
      {:ok, _} = Postgres.store([updated_sample], state)

      # Should still have only one sample
      stored = Repo.all(Forge.Schema.Sample)
      assert length(stored) == 1
      assert hd(stored).data["value"] == 99
    end

    test "returns error for invalid data", %{state: state} do
      # Create sample with missing required pipeline_id (will be caught by changeset)
      invalid_sample = %Sample{
        id: Ecto.UUID.generate(),
        pipeline: :test,
        # Invalid: data is required
        data: nil,
        created_at: DateTime.utc_now()
      }

      log =
        capture_log(fn ->
          assert {:error, _} = Postgres.store([invalid_sample], state)
        end)

      assert log =~ "Failed to store sample"
    end
  end

  describe "retrieve/2" do
    setup do
      {:ok, state} = Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{})

      sample_id = Ecto.UUID.generate()

      sample =
        Sample.new(
          id: sample_id,
          pipeline: :test_pipeline,
          data: %{value: 42}
        )

      {:ok, _} = Postgres.store([sample], state)

      %{state: state, sample_id: sample_id}
    end

    test "retrieves stored sample by ID", %{state: state, sample_id: sample_id} do
      {:ok, retrieved, _new_state} = Postgres.retrieve(sample_id, state)

      assert retrieved.id == sample_id
      assert retrieved.data["value"] == 42
    end

    test "returns error for non-existent sample", %{state: state} do
      {:error, :not_found} = Postgres.retrieve(Ecto.UUID.generate(), state)
    end

    test "includes measurements when retrieving", %{state: state, sample_id: sample_id} do
      # Add measurements to sample
      sample =
        Sample.new(
          id: sample_id,
          pipeline: :test_pipeline,
          data: %{value: 42},
          measurements: %{score: 0.95}
        )

      {:ok, _} = Postgres.store([sample], state)

      {:ok, retrieved, _} = Postgres.retrieve(sample_id, state)
      assert retrieved.measurements[:score] == 0.95
    end
  end

  describe "list/2" do
    setup do
      {:ok, state} = Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{})

      # Create samples with different statuses and timestamps
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600, :second)

      samples = [
        Sample.new(
          id: Ecto.UUID.generate(),
          pipeline: :test_pipeline,
          data: %{},
          created_at: past,
          status: :pending
        ),
        Sample.new(
          id: Ecto.UUID.generate(),
          pipeline: :test_pipeline,
          data: %{},
          created_at: now,
          status: :completed
        ),
        Sample.new(
          id: Ecto.UUID.generate(),
          pipeline: :test_pipeline,
          data: %{},
          created_at: now,
          status: :pending
        )
      ]

      {:ok, _} = Postgres.store(samples, state)

      %{state: state, now: now, past: past}
    end

    test "lists all samples with no filters", %{state: state} do
      {:ok, samples, _} = Postgres.list([], state)
      assert length(samples) == 3
    end

    test "filters by status", %{state: state} do
      {:ok, samples, _} = Postgres.list([status: :pending], state)
      assert length(samples) == 2
      assert Enum.all?(samples, fn s -> s.status == :pending end)
    end

    test "filters by timestamp (after)", %{state: state, past: past} do
      {:ok, samples, _} = Postgres.list([after: past], state)
      # Should get samples created after 'past' (2 samples)
      assert length(samples) >= 2
    end

    test "combines multiple filters", %{state: state, past: past} do
      {:ok, samples, _} = Postgres.list([status: :pending, after: past], state)
      assert Enum.all?(samples, fn s -> s.status == :pending end)
    end
  end

  describe "cleanup/1" do
    test "cleanup succeeds" do
      {:ok, state} = Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{})
      assert :ok = Postgres.cleanup(state)
    end
  end

  describe "record_stage_execution/3" do
    setup do
      {:ok, state} = Postgres.init(pipeline_name: :test_pipeline, pipeline_manifest: %{})

      sample_id = Ecto.UUID.generate()

      sample =
        Sample.new(
          id: sample_id,
          pipeline: :test_pipeline,
          data: %{value: 42}
        )

      {:ok, _} = Postgres.store([sample], state)

      %{sample_id: sample_id}
    end

    test "records stage execution history", %{sample_id: sample_id} do
      {:ok, _execution} =
        Postgres.record_stage_execution(
          sample_id,
          :transform_stage,
          config_hash: "abc123",
          status: "success",
          duration_ms: 150
        )

      executions = Repo.all(Forge.Schema.StageExecution)
      assert length(executions) == 1

      execution = hd(executions)
      assert execution.sample_id == sample_id
      assert execution.stage_name == "transform_stage"
      assert execution.status == "success"
      assert execution.duration_ms == 150
    end

    test "records failed stage execution", %{sample_id: sample_id} do
      {:ok, _execution} =
        Postgres.record_stage_execution(
          sample_id,
          :failing_stage,
          status: "failed",
          error_message: "Something went wrong"
        )

      execution = Repo.one(Forge.Schema.StageExecution)
      assert execution.status == "failed"
      assert execution.error_message == "Something went wrong"
    end
  end
end
