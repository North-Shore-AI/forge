defmodule Forge.Source.Generator do
  @moduledoc """
  Generator source that creates samples using a function.

  Generates samples dynamically using a generator function that receives
  an index and returns a data map.

  ## Options

    * `:count` - Number of samples to generate (required)
    * `:generator` - Function that takes index and returns data map (required)
    * `:batch_size` - Number of samples per fetch (default: count, all at once)

  ## Examples

      # Generate 100 random samples
      source Forge.Source.Generator,
        count: 100,
        generator: fn index ->
          %{id: index, value: :rand.uniform()}
        end

      # With batching
      source Forge.Source.Generator,
        count: 1000,
        batch_size: 100,
        generator: fn index ->
          %{index: index, data: generate_data(index)}
        end
  """

  @behaviour Forge.Source

  @impl true
  def init(opts) do
    count = Keyword.fetch!(opts, :count)
    generator = Keyword.fetch!(opts, :generator)
    batch_size = Keyword.get(opts, :batch_size, count)

    unless is_integer(count) and count > 0 do
      {:error, "count must be a positive integer"}
    else
      unless is_function(generator, 1) do
        {:error, "generator must be a function that takes one argument"}
      else
        {:ok,
         %{
           count: count,
           generator: generator,
           batch_size: batch_size,
           current: 0
         }}
      end
    end
  end

  @impl true
  def fetch(%{current: current, count: count} = state) when current >= count do
    {:done, state}
  end

  def fetch(
        %{current: current, count: count, generator: generator, batch_size: batch_size} = state
      ) do
    remaining = count - current
    batch = min(batch_size, remaining)

    samples =
      Enum.map(current..(current + batch - 1), fn index ->
        generator.(index)
      end)

    {:ok, samples, %{state | current: current + batch}}
  end

  @impl true
  def cleanup(_state), do: :ok
end
