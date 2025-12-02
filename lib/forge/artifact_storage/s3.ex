defmodule Forge.ArtifactStorage.S3 do
  @moduledoc """
  S3 adapter for artifact storage (stub implementation).

  This is a stub that will be fully implemented when ExAws is added as a dependency.
  For now, it provides the interface and basic structure.

  ## Future Configuration

      config :forge, :artifact_storage,
        adapter: Forge.ArtifactStorage.S3,
        bucket: "forge-artifacts",
        region: "us-east-1"

  ## Storage Layout

  Artifacts are stored content-addressed:

      s3://forge-artifacts/
        blobs/
          abc123...def  # SHA256 hash
          456789...012

  ## TODO

  - Add ExAws dependency
  - Implement actual S3 operations
  - Add multipart upload for large files (>5MB)
  - Add proper signed URL generation
  """

  @behaviour Forge.ArtifactStorage

  require Logger

  @impl true
  def put_blob(_sample_id, _key, _data, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def get_blob(_uri, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def signed_url(_uri, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def delete_blob(_uri) do
    {:error, :not_implemented}
  end
end
