defmodule Forge.AnvilBridgeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Forge.AnvilBridge

  describe "sample_to_dto/2" do
    test "converts sample with map data" do
      sample = %{
        id: "sample-123",
        pipeline_id: "pipeline-abc",
        data: %{
          "claim" => "The Earth orbits the Sun",
          "narrative_a" => "Narrative A content",
          "narrative_b" => "Narrative B content"
        },
        measurements: %{
          "embedding_distance" => 0.87,
          "text_length" => 150
        }
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert dto.sample_id == "sample-123"
      assert dto.title == "Claim: The Earth orbits the Sun..."
      assert dto.body =~ "Narrative A: Narrative A content"
      assert dto.body =~ "Narrative B: Narrative B content"
      assert dto.metadata.pipeline_id == "pipeline-abc"
      assert dto.metadata.measurements == sample.measurements
      assert dto.metadata.source_data == sample.data
    end

    test "converts sample with struct-style access" do
      sample = %{
        id: "sample-456",
        pipeline_id: "pipeline-xyz",
        data: %{
          text: "Plain text content"
        },
        measurements: %{}
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert dto.sample_id == "sample-456"
      assert dto.title == "Sample"
      assert dto.body == "Plain text content"
    end

    test "handles sample with title in data" do
      sample = %{
        id: "sample-789",
        pipeline_id: "pipeline-123",
        data: %{"title" => "Custom Title", "text" => "Content"},
        measurements: %{}
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert dto.title == "Custom Title"
      assert dto.body == "Content"
    end

    test "handles sample with narrative field" do
      sample = %{
        id: "sample-999",
        pipeline_id: "pipeline-456",
        data: %{"narrative" => "Single narrative content"},
        measurements: %{}
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert dto.body == "Single narrative content"
    end

    test "excludes measurements when include_measurements is false" do
      sample = %{
        id: "sample-111",
        pipeline_id: "pipeline-222",
        data: %{"text" => "Content"},
        measurements: %{"key" => "value"}
      }

      dto = AnvilBridge.sample_to_dto(sample, include_measurements: false)

      assert dto.metadata.measurements == %{}
    end

    test "handles sample with atom keys" do
      sample = %{
        id: "sample-222",
        pipeline_id: "pipeline-333",
        data: %{
          claim: "Atom key claim",
          narrative_a: "Atom narrative A",
          narrative_b: "Atom narrative B"
        },
        measurements: %{}
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert dto.title == "Claim: Atom key claim..."
      assert dto.body =~ "Narrative A: Atom narrative A"
      assert dto.body =~ "Narrative B: Atom narrative B"
    end

    test "falls back to JSON encoding for unknown data structure" do
      sample = %{
        id: "sample-333",
        pipeline_id: "pipeline-444",
        data: %{"complex" => %{"nested" => "data"}},
        measurements: %{}
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert dto.title == "Sample"
      assert dto.body =~ "complex"
      assert dto.body =~ "nested"
    end

    test "truncates long claims in title" do
      long_claim = String.duplicate("a", 100)

      sample = %{
        id: "sample-444",
        pipeline_id: "pipeline-555",
        data: %{"claim" => long_claim},
        measurements: %{}
      }

      dto = AnvilBridge.sample_to_dto(sample)

      assert String.length(dto.title) < String.length(long_claim)
      assert dto.title =~ "..."
    end
  end
end
