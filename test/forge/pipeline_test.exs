defmodule Forge.PipelineTest do
  use ExUnit.Case, async: true

  # Test stages for pipeline testing
  defmodule TestStage1 do
    @behaviour Forge.Stage
    def process(sample), do: {:ok, sample}
  end

  defmodule TestStage2 do
    @behaviour Forge.Stage
    def process(sample), do: {:ok, sample}
  end

  defmodule TestMeasurement do
    @behaviour Forge.Measurement
    def compute(_samples), do: {:ok, %{count: 1}}
  end

  defmodule TestPipelines do
    use Forge.Pipeline

    pipeline :simple do
      source(Forge.Source.Static, data: [%{value: 1}])
    end

    pipeline :with_stages do
      source(Forge.Source.Static, data: [%{value: 1}])
      stage(Forge.PipelineTest.TestStage1)
      stage(Forge.PipelineTest.TestStage2, opt: :value)
    end

    pipeline :with_measurements do
      source(Forge.Source.Static, data: [%{value: 1}])
      measurement(Forge.PipelineTest.TestMeasurement)
    end

    pipeline :with_storage do
      source(Forge.Source.Static, data: [%{value: 1}])
      storage(Forge.Storage.ETS, table: :test_table)
    end

    pipeline :complete do
      source(Forge.Source.Generator, count: 10, generator: fn i -> %{index: i} end)

      stage(Forge.PipelineTest.TestStage1)
      stage(Forge.PipelineTest.TestStage2)

      measurement(Forge.PipelineTest.TestMeasurement)

      storage(Forge.Storage.ETS, table: :complete_table)
    end
  end

  describe "pipeline DSL" do
    test "defines simple pipeline with only source" do
      config = TestPipelines.__pipeline__(:simple)

      assert config.name == :simple
      assert config.source_module == Forge.Source.Static
      assert config.source_opts == [data: [%{value: 1}]]
      assert config.stages == []
      assert config.measurements == []
      assert config.storage_module == nil
    end

    test "defines pipeline with stages" do
      config = TestPipelines.__pipeline__(:with_stages)

      assert config.stages == [
               {Forge.PipelineTest.TestStage1, []},
               {Forge.PipelineTest.TestStage2, [opt: :value]}
             ]
    end

    test "defines pipeline with measurements" do
      config = TestPipelines.__pipeline__(:with_measurements)

      assert config.measurements == [{Forge.PipelineTest.TestMeasurement, []}]
    end

    test "defines pipeline with storage" do
      config = TestPipelines.__pipeline__(:with_storage)

      assert config.storage_module == Forge.Storage.ETS
      assert config.storage_opts == [table: :test_table]
    end

    test "defines complete pipeline" do
      config = TestPipelines.__pipeline__(:complete)

      assert config.source_module == Forge.Source.Generator
      assert length(config.stages) == 2
      assert length(config.measurements) == 1
      assert config.storage_module == Forge.Storage.ETS
    end
  end

  describe "__pipeline__/1" do
    test "returns nil for non-existent pipeline" do
      assert TestPipelines.__pipeline__(:non_existent) == nil
    end
  end

  describe "__pipelines__/0" do
    test "returns list of all pipeline names" do
      names = TestPipelines.__pipelines__()

      assert :simple in names
      assert :with_stages in names
      assert :with_measurements in names
      assert :with_storage in names
      assert :complete in names
      assert length(names) == 5
    end
  end

  describe "pipeline validation" do
    test "raises error when source is not specified" do
      assert_raise ArgumentError, ~r/must specify a source/, fn ->
        defmodule InvalidPipeline do
          use Forge.Pipeline

          pipeline :invalid do
            stage(TestStage1)
          end
        end
      end
    end
  end

  describe "option evaluation" do
    test "pipeline DSL evaluates data options correctly" do
      config = TestPipelines.__pipeline__(:simple)

      # The data should be actual maps, not AST tuples
      assert is_list(config.source_opts[:data])

      # Get first element and verify it's an actual map, not AST
      first_item = hd(config.source_opts[:data])
      assert is_map(first_item)
      assert first_item == %{value: 1}
      refute match?({:%{}, _, _}, first_item)
    end

    test "pipeline DSL evaluates keyword list options correctly" do
      config = TestPipelines.__pipeline__(:with_storage)

      # Table name should be an atom, not AST
      assert config.storage_opts[:table] == :test_table
      refute match?({_, _, _}, config.storage_opts[:table])
    end

    test "pipeline DSL evaluates function options correctly" do
      config = TestPipelines.__pipeline__(:complete)

      # Generator should be a function, not AST
      generator = config.source_opts[:generator]
      assert is_function(generator, 1)

      # Verify function works
      result = generator.(5)
      assert is_map(result)
      assert result[:index] == 5
    end
  end
end
