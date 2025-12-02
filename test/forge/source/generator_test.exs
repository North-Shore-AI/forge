defmodule Forge.Source.GeneratorTest do
  use ExUnit.Case, async: true

  alias Forge.Source.Generator

  describe "init/1" do
    test "initializes with count and generator" do
      generator = fn i -> %{index: i} end
      {:ok, state} = Generator.init(count: 10, generator: generator)

      assert state.count == 10
      assert state.generator == generator
      assert state.batch_size == 10
      assert state.current == 0
    end

    test "supports custom batch size" do
      {:ok, state} =
        Generator.init(
          count: 100,
          batch_size: 25,
          generator: fn i -> %{i: i} end
        )

      assert state.batch_size == 25
    end

    test "returns error for invalid count" do
      {:error, msg} = Generator.init(count: 0, generator: fn _ -> %{} end)
      assert msg =~ "positive integer"

      {:error, msg} = Generator.init(count: -5, generator: fn _ -> %{} end)
      assert msg =~ "positive integer"
    end

    test "returns error for invalid generator" do
      {:error, msg} = Generator.init(count: 10, generator: "not a function")
      assert msg =~ "function that takes one argument"
    end
  end

  describe "fetch/1" do
    test "generates samples using generator function" do
      generator = fn i -> %{index: i, value: i * 2} end
      {:ok, state} = Generator.init(count: 3, generator: generator)
      {:ok, samples, _state} = Generator.fetch(state)

      assert samples == [
               %{index: 0, value: 0},
               %{index: 1, value: 2},
               %{index: 2, value: 4}
             ]
    end

    test "returns batches when batch_size is smaller than count" do
      generator = fn i -> %{i: i} end
      {:ok, state} = Generator.init(count: 5, batch_size: 2, generator: generator)

      # First batch
      {:ok, batch1, state} = Generator.fetch(state)
      assert batch1 == [%{i: 0}, %{i: 1}]
      assert state.current == 2

      # Second batch
      {:ok, batch2, state} = Generator.fetch(state)
      assert batch2 == [%{i: 2}, %{i: 3}]
      assert state.current == 4

      # Third batch (partial)
      {:ok, batch3, state} = Generator.fetch(state)
      assert batch3 == [%{i: 4}]
      assert state.current == 5

      # Done
      {:done, _state} = Generator.fetch(state)
    end

    test "returns done when all samples generated" do
      {:ok, state} = Generator.init(count: 2, generator: fn i -> %{i: i} end)
      {:ok, _samples, state} = Generator.fetch(state)
      {:done, _state} = Generator.fetch(state)
    end

    test "handles zero-count edge case in fetch" do
      # This shouldn't happen after init validation, but test the behavior
      state = %{count: 0, generator: fn _ -> %{} end, batch_size: 10, current: 0}
      {:done, _state} = Generator.fetch(state)
    end
  end

  describe "cleanup/1" do
    test "cleanup returns :ok" do
      {:ok, state} = Generator.init(count: 5, generator: fn i -> %{i: i} end)
      assert :ok = Generator.cleanup(state)
    end
  end

  describe "integration" do
    test "generates large number of samples in batches" do
      generator = fn i -> %{index: i, random: :rand.uniform()} end
      {:ok, state} = Generator.init(count: 1000, batch_size: 100, generator: generator)

      all_samples = collect_all_samples(state, [])

      assert length(all_samples) == 1000
      assert Enum.at(all_samples, 0).index == 0
      assert Enum.at(all_samples, 999).index == 999
    end
  end

  defp collect_all_samples(state, acc) do
    case Generator.fetch(state) do
      {:ok, samples, new_state} ->
        collect_all_samples(new_state, acc ++ samples)

      {:done, _state} ->
        acc
    end
  end
end
