defmodule Forge.Manifest.Hash do
  @moduledoc """
  Deterministic hashing for pipeline configurations.

  Provides stable hashing for drift detection and reproducibility.
  Uses sorted keys and deterministic serialization to ensure
  identical configs always produce identical hashes.
  """

  @doc """
  Compute deterministic hash of config (sorted keys, stable JSON).

  ## Examples

      iex> config = %{model: "gpt-4", temperature: 0.7}
      iex> hash1 = Forge.Manifest.Hash.config_hash(config)
      iex> hash2 = Forge.Manifest.Hash.config_hash(config)
      iex> hash1 == hash2
      true

      iex> config1 = %{a: 1, b: 2}
      iex> config2 = %{b: 2, a: 1}  # Different key order
      iex> Forge.Manifest.Hash.config_hash(config1) == Forge.Manifest.Hash.config_hash(config2)
      true
  """
  def config_hash(config) do
    # Normalize the config for deterministic hashing
    normalized = normalize(config)

    # Use deterministic term_to_binary
    binary = :erlang.term_to_binary(normalized, [:deterministic])

    # SHA256 hash
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Hash secrets by name only (never values).

  ## Examples

      iex> Forge.Manifest.Hash.secrets_hash(["api_key", "db_password"])
      "abc123..."

      iex> Forge.Manifest.Hash.secrets_hash([])
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  # empty hash
  """
  def secrets_hash(secret_names) when is_list(secret_names) do
    # Sort names for consistent ordering
    names = Enum.sort(secret_names)

    # Hash the sorted list
    binary = :erlang.term_to_binary(names, [:deterministic])

    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  # Private functions

  # Normalize data structures for deterministic hashing
  defp normalize(config) when is_map(config) do
    config
    # Sort by string representation of key
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {normalize_key(k), normalize(v)} end)
    |> Map.new()
  end

  defp normalize(list) when is_list(list) do
    Enum.map(list, &normalize/1)
  end

  defp normalize(value), do: value

  # Convert keys to strings for consistent hashing
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)
end
