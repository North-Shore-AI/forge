defmodule Forge.ArtifactStorage.Local do
  @moduledoc """
  Local filesystem adapter for artifact storage.

  Stores blobs on the local filesystem, useful for development and testing.
  Uses content-addressable storage (SHA256 hash) for deduplication.

  ## Configuration

      config :forge, :artifact_storage,
        adapter: Forge.ArtifactStorage.Local,
        base_path: "/tmp/forge_artifacts"

  ## Storage Layout

  Artifacts are stored in a flat directory structure:

      /tmp/forge_artifacts/
        blobs/
          abc123...def/  # SHA256 hash
          456789...012/

  """

  @behaviour Forge.ArtifactStorage

  require Logger

  @impl true
  def put_blob(_sample_id, _key, data, opts) when is_binary(data) do
    base_path = Keyword.get(opts, :base_path, default_base_path())
    content_hash = compute_hash(data)

    # Content-addressed: hash becomes filename
    blob_dir = Path.join(base_path, "blobs")
    File.mkdir_p!(blob_dir)

    blob_path = Path.join(blob_dir, content_hash)

    # Check if already exists (deduplication)
    if File.exists?(blob_path) do
      Logger.debug("Blob already exists: #{content_hash}")
      uri = "file://#{blob_path}"
      {:ok, uri}
    else
      case File.write(blob_path, data) do
        :ok ->
          uri = "file://#{blob_path}"
          {:ok, uri}

        {:error, reason} ->
          Logger.error("Failed to write blob: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @impl true
  def get_blob(uri, _opts) do
    path = uri_to_path(uri)

    case File.read(path) do
      {:ok, content} ->
        {:ok, content}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def signed_url(uri, opts) do
    # For local filesystem, just return the file:// URI
    # In a real implementation with HTTP server, this would generate
    # a time-limited token
    expires_in = Keyword.get(opts, :expires_in, 3600)

    # Simple implementation: just return the URI with expiry metadata
    # A production version would need an HTTP server with token validation
    {:ok, "#{uri}?expires_in=#{expires_in}"}
  end

  @impl true
  def delete_blob(uri) do
    path = uri_to_path(uri)

    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        # Already deleted, consider it success
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp compute_hash(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp uri_to_path("file://" <> path), do: path
  defp uri_to_path(path), do: path

  defp default_base_path do
    Path.join(System.tmp_dir!(), "forge_artifacts")
  end
end
