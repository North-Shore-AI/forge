defmodule Forge.Source.Static do
  @moduledoc """
  Static source that provides a pre-defined list of samples.

  Useful for testing and small datasets where all data is available in memory.

  ## Options

    * `:data` - List of data maps (required)

  ## Examples

      # In pipeline config
      source Forge.Source.Static, data: [
        %{value: 1},
        %{value: 2},
        %{value: 3}
      ]

      # Direct usage
      {:ok, state} = Forge.Source.Static.init(data: [%{x: 1}, %{x: 2}])
      {:ok, samples, state} = Forge.Source.Static.fetch(state)
      {:done, _state} = Forge.Source.Static.fetch(state)
  """

  @behaviour Forge.Source

  @impl true
  def init(opts) do
    data = Keyword.fetch!(opts, :data)

    unless is_list(data) do
      {:error, "data must be a list"}
    else
      {:ok, %{data: data, fetched: false}}
    end
  end

  @impl true
  def fetch(%{fetched: true} = state) do
    {:done, state}
  end

  def fetch(%{data: data} = state) do
    {:ok, data, %{state | fetched: true}}
  end

  @impl true
  def cleanup(_state), do: :ok
end
