defmodule Forge.Storage.ETS do
  @moduledoc """
  In-memory ETS-based storage backend.

  Fast, queryable storage using Erlang Term Storage. Data is lost when the
  process terminates.

  ## Options

    * `:table` - Table name (default: `:forge_samples`)
    * `:type` - Table type (default: `:set`, can be `:ordered_set`, `:bag`, `:duplicate_bag`)

  ## Examples

      # In pipeline config
      storage Forge.Storage.ETS, table: :my_samples

      # Manual usage
      {:ok, state} = Forge.Storage.ETS.init(table: :test)
      {:ok, state} = Forge.Storage.ETS.store(samples, state)
      {:ok, sample, state} = Forge.Storage.ETS.retrieve("id-123", state)
      {:ok, all, state} = Forge.Storage.ETS.list([], state)
      :ok = Forge.Storage.ETS.cleanup(state)
  """

  @behaviour Forge.Storage

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table, :forge_samples)
    type = Keyword.get(opts, :type, :set)

    # Create table if it doesn't exist
    case :ets.whereis(table) do
      :undefined ->
        ^table = :ets.new(table, [:named_table, type, :public, read_concurrency: true])

      _ref ->
        # Table already exists, use it
        :ok
    end

    {:ok, %{table: table}}
  end

  @impl true
  def store(samples, %{table: table} = state) do
    Enum.each(samples, fn sample ->
      :ets.insert(table, {sample.id, sample})
    end)

    {:ok, state}
  end

  @impl true
  def retrieve(id, %{table: table} = state) do
    case :ets.lookup(table, id) do
      [{^id, sample}] -> {:ok, sample, state}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def list(filters, %{table: table} = state) do
    samples =
      :ets.tab2list(table)
      |> Enum.map(fn {_id, sample} -> sample end)
      |> apply_filters(filters)

    {:ok, samples, state}
  end

  @impl true
  def cleanup(%{table: table}) do
    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    :ok
  end

  # Private helpers

  defp apply_filters(samples, []), do: samples

  defp apply_filters(samples, [{:pipeline, name} | rest]) do
    samples
    |> Enum.filter(&(&1.pipeline == name))
    |> apply_filters(rest)
  end

  defp apply_filters(samples, [{:status, status} | rest]) do
    samples
    |> Enum.filter(&(&1.status == status))
    |> apply_filters(rest)
  end

  defp apply_filters(samples, [{:after, datetime} | rest]) do
    samples
    |> Enum.filter(&(DateTime.compare(&1.created_at, datetime) == :gt))
    |> apply_filters(rest)
  end

  defp apply_filters(samples, [{:before, datetime} | rest]) do
    samples
    |> Enum.filter(&(DateTime.compare(&1.created_at, datetime) == :lt))
    |> apply_filters(rest)
  end

  defp apply_filters(samples, [_unknown | rest]) do
    apply_filters(samples, rest)
  end
end
