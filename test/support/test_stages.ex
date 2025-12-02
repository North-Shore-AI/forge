defmodule TestStages do
  @moduledoc """
  Test stage and measurement implementations for integration tests.
  """

  defmodule Normalize do
    @moduledoc "Normalizes raw_value to a 0-10 scale"
    @behaviour Forge.Stage

    def process(sample) do
      value = sample.data.raw_value / 100.0
      data = Map.put(sample.data, :normalized, value)
      {:ok, %{sample | data: data}}
    end
  end

  defmodule Validate do
    @moduledoc "Validates normalized values are in range"
    @behaviour Forge.Stage

    def process(sample) do
      if sample.data.normalized >= 0 and sample.data.normalized <= 10 do
        {:ok, sample}
      else
        {:skip, :out_of_range}
      end
    end
  end

  defmodule Enrich do
    @moduledoc "Enriches data with category based on normalized value"
    @behaviour Forge.Stage

    def process(sample) do
      category =
        cond do
          sample.data.normalized < 3 -> :low
          sample.data.normalized < 7 -> :medium
          true -> :high
        end

      data = Map.put(sample.data, :category, category)
      {:ok, %{sample | data: data}}
    end
  end

  defmodule Statistics do
    @moduledoc "Computes statistical measurements"
    @behaviour Forge.Measurement

    def compute(samples) do
      values = Enum.map(samples, & &1.data.normalized)

      stats = %{
        count: length(values),
        mean: Enum.sum(values) / length(values),
        min: Enum.min(values),
        max: Enum.max(values)
      }

      {:ok, stats}
    end
  end

  defmodule CategoryDistribution do
    @moduledoc "Computes category distribution"
    @behaviour Forge.Measurement

    def compute(samples) do
      distribution =
        samples
        |> Enum.group_by(& &1.data.category)
        |> Enum.map(fn {cat, samples} -> {cat, length(samples)} end)
        |> Map.new()

      {:ok, %{distribution: distribution}}
    end
  end

  defmodule SkipHalf do
    @moduledoc "Test stage that skips odd values"
    @behaviour Forge.Stage

    def process(sample) do
      if rem(sample.data.value, 2) == 0 do
        {:ok, sample}
      else
        {:skip, :odd_value}
      end
    end
  end

  # Runner test stages
  defmodule SimpleStage do
    @moduledoc "Simple test stage that doubles values"
    @behaviour Forge.Stage

    def process(sample) do
      data = Map.update!(sample.data, :value, &(&1 * 2))
      {:ok, %{sample | data: data}}
    end
  end

  defmodule FilterStage do
    @moduledoc "Test stage that filters based on value"
    @behaviour Forge.Stage

    def process(sample) do
      if sample.data.value > 5 do
        {:ok, sample}
      else
        {:skip, :too_small}
      end
    end
  end

  defmodule ErrorStage do
    @moduledoc "Test stage that always errors"
    @behaviour Forge.Stage

    def process(_sample) do
      {:error, :intentional_error}
    end
  end

  defmodule SyncMeasurement do
    @moduledoc "Synchronous test measurement"
    @behaviour Forge.Measurement

    def compute(samples) do
      count = length(samples)
      sum = Enum.reduce(samples, 0, fn s, acc -> acc + s.data.value end)
      {:ok, %{count: count, sum: sum}}
    end
  end

  defmodule AsyncMeasurement do
    @moduledoc "Asynchronous test measurement"
    @behaviour Forge.Measurement

    def compute(samples) do
      {:ok, %{async_count: length(samples)}}
    end

    def async?(), do: true
  end
end
