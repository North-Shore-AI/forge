defmodule Forge.ManifestTest do
  use ExUnit.Case, async: true

  alias Forge.Manifest

  describe "from_pipeline/2" do
    test "captures source config" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [batch_size: 100, dataset: "test"],
        stages: [],
        measurements: []
      }

      manifest = Manifest.from_pipeline(pipeline, git_sha: "abc123")

      assert manifest.pipeline_name == :test_pipeline
      assert manifest.source_config_hash != nil
      assert is_binary(manifest.source_config_hash)
      assert manifest.git_sha == "abc123"
      assert %DateTime{} = manifest.created_at
    end

    test "hashes stage configs" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [
          {StageOne, [param: "value1", count: 10]},
          {StageTwo, [enabled: true]}
        ],
        measurements: []
      }

      manifest = Manifest.from_pipeline(pipeline)

      assert length(manifest.stage_configs) == 2

      [stage1, stage2] = manifest.stage_configs

      assert stage1.module == "StageOne"
      assert stage1.config == %{param: "value1", count: 10}
      assert is_binary(stage1.config_hash)

      assert stage2.module == "StageTwo"
      assert stage2.config == %{enabled: true}
      assert is_binary(stage2.config_hash)
    end

    test "hashes measurement configs" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: [
          {MeasurementOne, [threshold: 0.5]},
          {MeasurementTwo, []}
        ]
      }

      manifest = Manifest.from_pipeline(pipeline)

      assert length(manifest.measurement_configs) == 2

      [m1, m2] = manifest.measurement_configs

      assert m1.module == "MeasurementOne"
      assert m1.config == %{threshold: 0.5}
      assert is_binary(m1.config_hash)

      assert m2.module == "MeasurementTwo"
      assert m2.config == %{}
      assert is_binary(m2.config_hash)
    end

    test "hashes secrets by name only" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: []
      }

      manifest = Manifest.from_pipeline(pipeline, secrets: ["api_key", "db_password"])

      assert manifest.secrets_used == ["api_key", "db_password"]
      assert is_binary(manifest.secrets_hash)
    end

    test "handles empty secrets" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: []
      }

      manifest = Manifest.from_pipeline(pipeline)

      assert manifest.secrets_used == []
      assert is_binary(manifest.secrets_hash)
    end

    test "detects git SHA if available" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: []
      }

      manifest = Manifest.from_pipeline(pipeline)

      # git_sha will be nil if not in a git repo or git command fails
      # or a string if git is available
      assert is_nil(manifest.git_sha) or is_binary(manifest.git_sha)
    end
  end

  describe "hash/1" do
    test "produces deterministic hash" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [batch_size: 100],
        stages: [{Stage1, [param: "value"]}],
        measurements: []
      }

      manifest1 = Manifest.from_pipeline(pipeline, git_sha: "abc123")
      manifest2 = Manifest.from_pipeline(pipeline, git_sha: "abc123")

      hash1 = Manifest.hash(manifest1)
      hash2 = Manifest.hash(manifest2)

      # Hashes should be identical even though created_at differs
      assert hash1 == hash2
      assert is_binary(hash1)
      # SHA256 in hex
      assert String.length(hash1) == 64
    end

    test "detects config changes" do
      pipeline1 = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [batch_size: 100],
        stages: [],
        measurements: []
      }

      pipeline2 = %{
        name: :test_pipeline,
        source_module: TestSource,
        # Changed
        source_opts: [batch_size: 200],
        stages: [],
        measurements: []
      }

      manifest1 = Manifest.from_pipeline(pipeline1, git_sha: "abc123")
      manifest2 = Manifest.from_pipeline(pipeline2, git_sha: "abc123")

      hash1 = Manifest.hash(manifest1)
      hash2 = Manifest.hash(manifest2)

      assert hash1 != hash2
    end

    test "detects stage addition" do
      pipeline1 = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: []
      }

      pipeline2 = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        # Added stage
        stages: [{NewStage, []}],
        measurements: []
      }

      manifest1 = Manifest.from_pipeline(pipeline1)
      manifest2 = Manifest.from_pipeline(pipeline2)

      assert Manifest.hash(manifest1) != Manifest.hash(manifest2)
    end
  end

  describe "equivalent?/2" do
    test "detects identical configs" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [batch_size: 100],
        stages: [{Stage1, [param: "value"]}],
        measurements: [{Measure1, [threshold: 0.5]}]
      }

      manifest1 = Manifest.from_pipeline(pipeline, git_sha: "abc123")
      manifest2 = Manifest.from_pipeline(pipeline, git_sha: "abc123")

      assert Manifest.equivalent?(manifest1, manifest2)
    end

    test "detects config drift" do
      pipeline1 = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [batch_size: 100],
        stages: [],
        measurements: []
      }

      pipeline2 = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [batch_size: 200],
        stages: [],
        measurements: []
      }

      manifest1 = Manifest.from_pipeline(pipeline1)
      manifest2 = Manifest.from_pipeline(pipeline2)

      refute Manifest.equivalent?(manifest1, manifest2)
    end

    test "detects git SHA changes" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: []
      }

      manifest1 = Manifest.from_pipeline(pipeline, git_sha: "abc123")
      manifest2 = Manifest.from_pipeline(pipeline, git_sha: "def456")

      refute Manifest.equivalent?(manifest1, manifest2)
    end

    test "ignores created_at differences" do
      pipeline = %{
        name: :test_pipeline,
        source_module: TestSource,
        source_opts: [],
        stages: [],
        measurements: []
      }

      manifest1 = Manifest.from_pipeline(pipeline, git_sha: "abc123")
      # Create manifest at a different time by explicitly setting a different timestamp
      manifest2 = Manifest.from_pipeline(pipeline, git_sha: "abc123")
      manifest2 = %{manifest2 | created_at: DateTime.add(manifest2.created_at, 1, :second)}

      # Timestamps are different but configs are the same
      assert manifest1.created_at != manifest2.created_at
      assert Manifest.equivalent?(manifest1, manifest2)
    end
  end
end
