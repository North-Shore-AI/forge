defmodule Forge.Manifest do
  @moduledoc """
  Pipeline manifest for reproducibility and lineage tracking.

  Captures the complete configuration of a pipeline run, including:
  - Source, stage, and measurement configurations
  - Git SHA for code versioning
  - Secrets used (names only, never values)
  - Deterministic hashing for drift detection

  ## Example

      manifest = Forge.Manifest.from_pipeline(pipeline, git_sha: "abc123")

      # Hash for comparison
      hash = Forge.Manifest.hash(manifest)

      # Check equivalence
      Forge.Manifest.equivalent?(manifest1, manifest2)
  """

  @type t :: %__MODULE__{
          pipeline_name: atom(),
          source_config_hash: String.t(),
          stage_configs: [map()],
          measurement_configs: [map()],
          git_sha: String.t() | nil,
          created_at: DateTime.t(),
          secrets_used: [String.t()],
          secrets_hash: String.t()
        }

  defstruct [
    :pipeline_name,
    :source_config_hash,
    :stage_configs,
    :measurement_configs,
    :git_sha,
    :created_at,
    :secrets_used,
    :secrets_hash
  ]

  @doc """
  Generate manifest from pipeline config.

  ## Options

    * `:git_sha` - Git commit SHA (default: attempts to detect from git)
    * `:secrets` - List of secret names used (default: [])

  ## Examples

      pipeline = %{
        name: :my_pipeline,
        source_module: MySource,
        source_opts: [batch_size: 100],
        stages: [{MyStage, [param: "value"]}],
        measurements: [{MyMeasurement, []}]
      }

      manifest = Forge.Manifest.from_pipeline(pipeline)
  """
  def from_pipeline(pipeline, opts \\ []) do
    secrets = Keyword.get(opts, :secrets, [])
    git_sha = Keyword.get(opts, :git_sha, detect_git_sha())

    # Hash the source config
    source_config = Map.get(pipeline, :source_opts, []) |> Map.new()
    source_config_hash = Forge.Manifest.Hash.config_hash(source_config)

    # Build stage configs with hashes
    stage_configs =
      pipeline
      |> Map.get(:stages, [])
      |> Enum.map(fn {module, opts} ->
        config = Map.new(opts)

        %{
          module: module_name(module),
          config: config,
          config_hash: Forge.Manifest.Hash.config_hash(config)
        }
      end)

    # Build measurement configs with hashes
    measurement_configs =
      pipeline
      |> Map.get(:measurements, [])
      |> Enum.map(fn {module, opts} ->
        config = Map.new(opts)

        %{
          module: module_name(module),
          config: config,
          config_hash: Forge.Manifest.Hash.config_hash(config)
        }
      end)

    # Hash the secrets list (names only, never values)
    secrets_hash = Forge.Manifest.Hash.secrets_hash(secrets)

    %__MODULE__{
      pipeline_name: Map.get(pipeline, :name),
      source_config_hash: source_config_hash,
      stage_configs: stage_configs,
      measurement_configs: measurement_configs,
      git_sha: git_sha,
      created_at: DateTime.utc_now(),
      secrets_used: secrets,
      secrets_hash: secrets_hash
    }
  end

  @doc """
  Hash the manifest for comparison.

  Produces a deterministic SHA256 hash of the manifest contents.
  """
  def hash(%__MODULE__{} = manifest) do
    # Convert to map, exclude created_at (which varies)
    map =
      manifest
      |> Map.from_struct()
      |> Map.delete(:created_at)

    Forge.Manifest.Hash.config_hash(map)
  end

  @doc """
  Check if two manifests are equivalent.

  Manifests are considered equivalent if their hashes match,
  meaning the pipeline configuration is identical.
  """
  def equivalent?(%__MODULE__{} = m1, %__MODULE__{} = m2) do
    hash(m1) == hash(m2)
  end

  # Private helpers

  defp module_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp detect_git_sha do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
