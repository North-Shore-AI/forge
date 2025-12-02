defmodule Forge.ArtifactStorage do
  @moduledoc """
  Behaviour for artifact storage backends.

  Artifacts are large binary or text payloads that don't belong in Postgres,
  such as raw narratives, LLM responses, embeddings, or serialized models.

  ## Callbacks

  - `put_blob/4` - Store a blob and return its URI
  - `get_blob/2` - Retrieve a blob by URI
  - `signed_url/2` - Generate time-limited signed URL for blob access
  - `delete_blob/1` - Remove a blob from storage

  ## Content Addressing

  All adapters should use content-addressable storage (SHA256 hash) for
  immutability and deduplication.

  ## Examples

      # Store a blob
      {:ok, uri} = adapter.put_blob(sample_id, "raw_narrative", content, bucket: "forge-artifacts")

      # Retrieve it
      {:ok, content} = adapter.get_blob(uri)

      # Get signed URL for frontend access
      {:ok, url} = adapter.signed_url(uri, expires_in: 3600)
  """

  @doc """
  Store a blob and return its storage URI.

  ## Parameters

    * `sample_id` - The sample ID this artifact belongs to
    * `key` - The artifact key (e.g., "raw_narrative", "embedding")
    * `data` - The binary content to store
    * `opts` - Storage-specific options

  ## Returns

    * `{:ok, uri}` - Success with storage URI
    * `{:error, reason}` - Failure
  """
  @callback put_blob(
              sample_id :: String.t(),
              key :: String.t(),
              data :: binary(),
              opts :: keyword()
            ) ::
              {:ok, uri :: String.t()} | {:error, term()}

  @doc """
  Retrieve a blob by its storage URI.

  ## Parameters

    * `uri` - The storage URI returned by `put_blob/4`
    * `opts` - Storage-specific options

  ## Returns

    * `{:ok, binary}` - Success with blob content
    * `{:error, reason}` - Failure (e.g., not found)
  """
  @callback get_blob(uri :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}

  @doc """
  Generate a time-limited signed URL for blob access.

  Useful for providing temporary access to artifacts without exposing
  storage credentials.

  ## Parameters

    * `uri` - The storage URI
    * `opts` - Options including `:expires_in` (seconds)

  ## Returns

    * `{:ok, url}` - Signed URL string
    * `{:error, reason}` - Failure
  """
  @callback signed_url(uri :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Delete a blob from storage.

  ## Parameters

    * `uri` - The storage URI to delete

  ## Returns

    * `:ok` - Success
    * `{:error, reason}` - Failure
  """
  @callback delete_blob(uri :: String.t()) ::
              :ok | {:error, term()}
end
