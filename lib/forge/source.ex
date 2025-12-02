defmodule Forge.Source do
  @moduledoc """
  Behaviour for sample sources.

  Sources provide samples to pipelines. They can be static lists, generators,
  database queries, or any other data provider.

  ## Lifecycle

  1. `init/1` - Initialize the source with configuration options
  2. `fetch/1` - Retrieve the next batch of samples (called repeatedly)
  3. `cleanup/1` - Clean up resources when done

  ## Examples

      defmodule MySource do
        @behaviour Forge.Source

        def init(opts) do
          {:ok, %{data: Keyword.fetch!(opts, :data), index: 0}}
        end

        def fetch(%{data: data, index: index} = state) do
          if index < length(data) do
            sample = Enum.at(data, index)
            {:ok, [sample], %{state | index: index + 1}}
          else
            {:done, state}
          end
        end

        def cleanup(_state), do: :ok
      end
  """

  @doc """
  Initialize the source with the given options.

  Returns `{:ok, state}` with initial state or `{:error, reason}` on failure.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Fetch the next batch of samples.

  Returns:
  - `{:ok, samples, new_state}` - Batch of sample data maps with updated state
  - `{:done, state}` - No more samples available
  """
  @callback fetch(state :: any()) ::
              {:ok, samples :: [map()], new_state :: any()} | {:done, state :: any()}

  @doc """
  Clean up any resources held by the source.
  """
  @callback cleanup(state :: any()) :: :ok
end
