defmodule Forge.Storage.ETSTest do
  use ExUnit.Case, async: true

  alias Forge.{Sample, Storage.ETS}

  setup do
    # Use unique table name for each test
    table = :"test_#{:erlang.unique_integer([:positive])}"
    {:ok, table: table}
  end

  describe "init/1" do
    test "creates ETS table with default options", %{table: table} do
      {:ok, state} = ETS.init(table: table)

      assert state.table == table
      assert :ets.whereis(table) != :undefined
    end

    test "uses default table name when not specified" do
      {:ok, state} = ETS.init([])

      assert state.table == :forge_samples
      assert :ets.whereis(:forge_samples) != :undefined

      # Cleanup
      :ets.delete(:forge_samples)
    end

    test "supports ordered_set type", %{table: table} do
      {:ok, _state} = ETS.init(table: table, type: :ordered_set)

      info = :ets.info(table)
      assert info[:type] == :ordered_set
    end

    test "handles existing table gracefully" do
      table = :existing_table
      :ets.new(table, [:named_table, :set, :public])

      {:ok, state} = ETS.init(table: table)
      assert state.table == table

      :ets.delete(table)
    end
  end

  describe "store/2" do
    test "stores samples in ETS table", %{table: table} do
      {:ok, state} = ETS.init(table: table)

      samples = [
        Sample.new(id: "1", pipeline: :test, data: %{value: 1}),
        Sample.new(id: "2", pipeline: :test, data: %{value: 2})
      ]

      {:ok, new_state} = ETS.store(samples, state)

      assert new_state == state
      assert :ets.lookup(table, "1") == [{"1", Enum.at(samples, 0)}]
      assert :ets.lookup(table, "2") == [{"2", Enum.at(samples, 1)}]
    end

    test "overwrites existing samples with same id", %{table: table} do
      {:ok, state} = ETS.init(table: table)

      sample1 = Sample.new(id: "1", pipeline: :test, data: %{value: 1})
      sample2 = Sample.new(id: "1", pipeline: :test, data: %{value: 999})

      {:ok, _state} = ETS.store([sample1], state)
      {:ok, _state} = ETS.store([sample2], state)

      [{_id, stored}] = :ets.lookup(table, "1")
      assert stored.data.value == 999
    end
  end

  describe "retrieve/2" do
    test "retrieves sample by id", %{table: table} do
      {:ok, state} = ETS.init(table: table)
      sample = Sample.new(id: "test-id", pipeline: :test, data: %{value: 42})

      {:ok, state} = ETS.store([sample], state)
      {:ok, retrieved, _state} = ETS.retrieve("test-id", state)

      assert retrieved.id == "test-id"
      assert retrieved.data.value == 42
    end

    test "returns error for non-existent id", %{table: table} do
      {:ok, state} = ETS.init(table: table)
      {:error, :not_found} = ETS.retrieve("non-existent", state)
    end
  end

  describe "list/2" do
    setup %{table: table} do
      {:ok, state} = ETS.init(table: table)

      samples = [
        Sample.new(id: "1", pipeline: :pipeline_a, data: %{}, status: :pending),
        Sample.new(id: "2", pipeline: :pipeline_a, data: %{}, status: :ready),
        Sample.new(id: "3", pipeline: :pipeline_b, data: %{}, status: :ready),
        Sample.new(id: "4", pipeline: :pipeline_b, data: %{}, status: :skipped)
      ]

      {:ok, state} = ETS.store(samples, state)

      {:ok, state: state, samples: samples}
    end

    test "lists all samples with no filters", %{state: state, samples: samples} do
      {:ok, listed, _state} = ETS.list([], state)

      assert length(listed) == 4
      assert Enum.sort_by(listed, & &1.id) == Enum.sort_by(samples, & &1.id)
    end

    test "filters by pipeline", %{state: state} do
      {:ok, listed, _state} = ETS.list([pipeline: :pipeline_a], state)

      assert length(listed) == 2
      assert Enum.all?(listed, &(&1.pipeline == :pipeline_a))
    end

    test "filters by status", %{state: state} do
      {:ok, listed, _state} = ETS.list([status: :ready], state)

      assert length(listed) == 2
      assert Enum.all?(listed, &(&1.status == :ready))
    end

    test "filters by multiple criteria", %{state: state} do
      {:ok, listed, _state} = ETS.list([pipeline: :pipeline_b, status: :ready], state)

      assert length(listed) == 1
      assert hd(listed).id == "3"
    end

    test "filters by datetime after", %{state: state, table: _table} do
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600, :second)
      future = DateTime.add(now, 3600, :second)

      sample_past = Sample.new(id: "past", pipeline: :test, data: %{}, created_at: past)
      sample_future = Sample.new(id: "future", pipeline: :test, data: %{}, created_at: future)

      {:ok, state} = ETS.store([sample_past, sample_future], state)

      {:ok, listed, _state} = ETS.list([after: now], state)

      assert length(listed) == 1
      assert hd(listed).id == "future"
    end

    test "filters by datetime before", %{state: state, table: _table} do
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600, :second)

      sample_past = Sample.new(id: "past", pipeline: :test, data: %{}, created_at: past)

      {:ok, state} = ETS.store([sample_past], state)

      {:ok, listed, _state} = ETS.list([before: now], state)

      ids = Enum.map(listed, & &1.id)
      assert "past" in ids
    end

    test "ignores unknown filter keys", %{state: state} do
      {:ok, listed, _state} = ETS.list([unknown_key: :value], state)

      # Should return all samples, ignoring unknown filter
      assert length(listed) == 4
    end
  end

  describe "cleanup/1" do
    test "deletes ETS table", %{table: table} do
      {:ok, state} = ETS.init(table: table)

      assert :ets.whereis(table) != :undefined

      :ok = ETS.cleanup(state)

      assert :ets.whereis(table) == :undefined
    end

    test "handles already deleted table gracefully", %{table: table} do
      {:ok, state} = ETS.init(table: table)
      :ets.delete(table)

      assert :ok = ETS.cleanup(state)
    end
  end
end
