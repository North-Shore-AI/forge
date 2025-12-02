defmodule Forge.Manifest.HashTest do
  use ExUnit.Case, async: true

  alias Forge.Manifest.Hash

  describe "config_hash/1" do
    test "produces deterministic hash for maps" do
      config = %{model: "gpt-4", temperature: 0.7, max_tokens: 100}

      hash1 = Hash.config_hash(config)
      hash2 = Hash.config_hash(config)

      assert hash1 == hash2
      assert is_binary(hash1)
      # SHA256 in hex
      assert String.length(hash1) == 64
    end

    test "is order-independent for map keys" do
      config1 = %{a: 1, b: 2, c: 3}
      config2 = %{c: 3, a: 1, b: 2}
      config3 = %{b: 2, c: 3, a: 1}

      hash1 = Hash.config_hash(config1)
      hash2 = Hash.config_hash(config2)
      hash3 = Hash.config_hash(config3)

      assert hash1 == hash2
      assert hash2 == hash3
    end

    test "detects value changes" do
      config1 = %{model: "gpt-4", temperature: 0.7}
      config2 = %{model: "gpt-4", temperature: 0.8}

      hash1 = Hash.config_hash(config1)
      hash2 = Hash.config_hash(config2)

      assert hash1 != hash2
    end

    test "detects key additions" do
      config1 = %{model: "gpt-4"}
      config2 = %{model: "gpt-4", temperature: 0.7}

      hash1 = Hash.config_hash(config1)
      hash2 = Hash.config_hash(config2)

      assert hash1 != hash2
    end

    test "handles nested maps" do
      config1 = %{
        model: "gpt-4",
        params: %{temperature: 0.7, top_p: 0.9}
      }

      config2 = %{
        model: "gpt-4",
        # Different order
        params: %{top_p: 0.9, temperature: 0.7}
      }

      hash1 = Hash.config_hash(config1)
      hash2 = Hash.config_hash(config2)

      # Should be the same despite nested map key order
      assert hash1 == hash2
    end

    test "handles lists" do
      config1 = %{stages: ["stage1", "stage2", "stage3"]}
      config2 = %{stages: ["stage1", "stage2", "stage3"]}

      hash1 = Hash.config_hash(config1)
      hash2 = Hash.config_hash(config2)

      assert hash1 == hash2
    end

    test "detects list order changes" do
      config1 = %{stages: ["stage1", "stage2"]}
      # Different order
      config2 = %{stages: ["stage2", "stage1"]}

      hash1 = Hash.config_hash(config1)
      hash2 = Hash.config_hash(config2)

      # List order matters
      assert hash1 != hash2
    end

    test "handles atom keys" do
      config = %{model: "gpt-4", temperature: 0.7}

      hash = Hash.config_hash(config)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end

    test "handles string keys" do
      config = %{"model" => "gpt-4", "temperature" => 0.7}

      hash = Hash.config_hash(config)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end

    test "normalizes atom and string keys identically" do
      config_atoms = %{model: "gpt-4", temperature: 0.7}
      config_strings = %{"model" => "gpt-4", "temperature" => 0.7}

      hash1 = Hash.config_hash(config_atoms)
      hash2 = Hash.config_hash(config_strings)

      # Should produce the same hash after normalization
      assert hash1 == hash2
    end

    test "handles empty maps" do
      config = %{}

      hash = Hash.config_hash(config)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end

    test "handles complex nested structures" do
      config = %{
        source: %{
          type: "api",
          config: %{url: "https://example.com", batch_size: 100}
        },
        stages: [
          %{name: "filter", params: %{threshold: 0.5}},
          %{name: "transform", params: %{model: "gpt-4"}}
        ],
        measurements: [
          %{type: "accuracy"},
          %{type: "latency", unit: "ms"}
        ]
      }

      hash1 = Hash.config_hash(config)
      hash2 = Hash.config_hash(config)

      assert hash1 == hash2
    end
  end

  describe "secrets_hash/1" do
    test "produces deterministic hash for secret names" do
      secrets = ["api_key", "db_password", "oauth_token"]

      hash1 = Hash.secrets_hash(secrets)
      hash2 = Hash.secrets_hash(secrets)

      assert hash1 == hash2
      assert is_binary(hash1)
      assert String.length(hash1) == 64
    end

    test "is order-independent" do
      secrets1 = ["api_key", "db_password", "oauth_token"]
      secrets2 = ["oauth_token", "api_key", "db_password"]
      secrets3 = ["db_password", "oauth_token", "api_key"]

      hash1 = Hash.secrets_hash(secrets1)
      hash2 = Hash.secrets_hash(secrets2)
      hash3 = Hash.secrets_hash(secrets3)

      # All should produce the same hash after sorting
      assert hash1 == hash2
      assert hash2 == hash3
    end

    test "detects secret additions" do
      secrets1 = ["api_key", "db_password"]
      secrets2 = ["api_key", "db_password", "oauth_token"]

      hash1 = Hash.secrets_hash(secrets1)
      hash2 = Hash.secrets_hash(secrets2)

      assert hash1 != hash2
    end

    test "detects secret removals" do
      secrets1 = ["api_key", "db_password", "oauth_token"]
      secrets2 = ["api_key", "db_password"]

      hash1 = Hash.secrets_hash(secrets1)
      hash2 = Hash.secrets_hash(secrets2)

      assert hash1 != hash2
    end

    test "handles empty list" do
      secrets = []

      hash = Hash.secrets_hash(secrets)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end

    test "produces different hash for different names" do
      secrets1 = ["api_key_prod"]
      secrets2 = ["api_key_staging"]

      hash1 = Hash.secrets_hash(secrets1)
      hash2 = Hash.secrets_hash(secrets2)

      assert hash1 != hash2
    end
  end
end
