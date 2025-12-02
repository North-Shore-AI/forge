defmodule Forge.Storage do
  @moduledoc """
  Behaviour for sample storage backends.

  Storage backends persist samples after pipeline processing. They can be
  in-memory, disk-based, database-backed, or stream to external systems.

  ## Lifecycle

  1. `init/1` - Initialize storage with configuration
  2. `store/2` - Store a batch of samples
  3. `retrieve/2` - Retrieve a sample by ID (optional)
  4. `list/2` - List samples with filters (optional)
  5. `cleanup/1` - Clean up resources

  ## Examples

      defmodule MyStorage do
        @behaviour Forge.Storage

        def init(opts) do
          path = Keyword.fetch!(opts, :path)
          File.mkdir_p!(path)
          {:ok, %{path: path}}
        end

        def store(samples, %{path: path} = state) do
          Enum.each(samples, fn sample ->
            file = Path.join(path, "\#{sample.id}.json")
            File.write!(file, Jason.encode!(sample))
          end)
          {:ok, state}
        end

        def cleanup(_state), do: :ok
      end
  """

  @doc """
  Initialize the storage backend with configuration options.

  Returns `{:ok, state}` with initial state or `{:error, reason}` on failure.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Store a batch of samples.

  Returns `{:ok, new_state}` on success or `{:error, reason}` on failure.
  """
  @callback store(samples :: [Forge.Sample.t()], state :: any()) ::
              {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Retrieve a sample by ID.

  Returns `{:ok, sample, new_state}` if found, `{:error, :not_found}` if not found,
  or `{:error, reason}` on other failures.

  This callback is optional - not all storage backends need to support retrieval.
  """
  @callback retrieve(id :: String.t(), state :: any()) ::
              {:ok, Forge.Sample.t(), state :: any()} | {:error, reason :: any()}

  @doc """
  List samples matching the given filters.

  Filters are backend-specific keyword lists. Common filters include:
  - `pipeline: atom()` - Filter by pipeline name
  - `status: atom()` - Filter by status
  - `after: DateTime.t()` - Samples created after timestamp
  - `before: DateTime.t()` - Samples created before timestamp

  Returns `{:ok, samples, new_state}` or `{:error, reason}`.

  This callback is optional - not all storage backends need to support listing.
  """
  @callback list(filters :: keyword(), state :: any()) ::
              {:ok, [Forge.Sample.t()], state :: any()} | {:error, reason :: any()}

  @doc """
  Clean up any resources held by the storage backend.
  """
  @callback cleanup(state :: any()) :: :ok

  @optional_callbacks [retrieve: 2, list: 2]
end
