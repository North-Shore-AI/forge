defmodule Forge.Source.StaticTest do
  use ExUnit.Case, async: true

  alias Forge.Source.Static

  describe "init/1" do
    test "initializes with data list" do
      {:ok, state} = Static.init(data: [%{a: 1}, %{b: 2}])

      assert state.data == [%{a: 1}, %{b: 2}]
      assert state.fetched == false
    end

    test "returns error for non-list data" do
      {:error, msg} = Static.init(data: %{not: :a_list})
      assert msg =~ "must be a list"
    end

    test "raises on missing data option" do
      assert_raise KeyError, fn ->
        Static.init([])
      end
    end
  end

  describe "fetch/1" do
    test "returns all data on first fetch" do
      {:ok, state} = Static.init(data: [%{value: 1}, %{value: 2}, %{value: 3}])
      {:ok, samples, new_state} = Static.fetch(state)

      assert samples == [%{value: 1}, %{value: 2}, %{value: 3}]
      assert new_state.fetched == true
    end

    test "returns done on subsequent fetches" do
      {:ok, state} = Static.init(data: [%{value: 1}])
      {:ok, _samples, state} = Static.fetch(state)
      {:done, _state} = Static.fetch(state)
    end

    test "handles empty data list" do
      {:ok, state} = Static.init(data: [])
      {:ok, samples, _state} = Static.fetch(state)

      assert samples == []
    end
  end

  describe "cleanup/1" do
    test "cleanup returns :ok" do
      {:ok, state} = Static.init(data: [])
      assert :ok = Static.cleanup(state)
    end
  end
end
