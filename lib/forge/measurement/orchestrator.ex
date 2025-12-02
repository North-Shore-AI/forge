defmodule Forge.Measurement.Orchestrator do
  @moduledoc """
  Orchestrates measurement computation with support for:

  - Idempotency via deterministic measurement IDs
  - Async execution with Task.Supervisor
  - Batch processing for vectorized measurements
  - Measurement dependencies and execution ordering
  - Version tracking and cache invalidation
  - Telemetry integration

  ## Usage

      # Compute single measurement
      {:ok, :computed, value} = Orchestrator.measure_sample(sample_id, MyMeasurement, [])

      # Batch processing
      results = Orchestrator.measure_batch(sample_ids, MyMeasurement, [])

      # Async execution
      task = Orchestrator.measure_async(sample_ids, MyMeasurement, [])
      results = Task.await(task)

      # With dependencies
      {:ok, :computed, value} = Orchestrator.measure_with_dependencies(
        sample_id,
        MeasurementWithDeps,
        []
      )
  """

  import Ecto.Query
  alias Forge.{Repo, Measurement, Telemetry}
  alias Forge.Schema.{MeasurementRecord, Sample}

  @doc """
  Computes or retrieves a measurement for a single sample.

  Returns:
  - `{:ok, :computed, value}` - Measurement was computed and stored
  - `{:ok, :cached, value}` - Measurement was retrieved from cache
  - `{:error, reason}` - Computation failed
  """
  def measure_sample(sample_id, measurement_module, opts \\ []) do
    key = measurement_module.key()
    version = measurement_module.version()

    # Check for cached measurement
    case get_measurement(sample_id, key, version: version) do
      {:ok, cached} ->
        emit_measurement_telemetry(sample_id, key, 0, :cached)
        {:ok, :cached, cached.value}

      {:error, :not_found} ->
        compute_and_store_measurement(sample_id, measurement_module, key, version, opts)
    end
  end

  @doc """
  Computes measurements for multiple samples.

  Respects batch_capable? and batch_size settings for efficient processing.

  Returns a list of results in the same order as sample_ids:
  - `{:ok, :computed, value}` - Measurement was computed
  - `{:ok, :cached, value}` - Measurement was cached
  - `{:error, reason}` - Computation failed
  """
  def measure_batch(sample_ids, measurement_module, opts \\ []) do
    key = measurement_module.key()
    version = measurement_module.version()

    # Fetch all samples and cached measurements
    samples = get_samples_by_ids(sample_ids)
    cached = get_measurements_batch(sample_ids, key, version)

    cached_ids = MapSet.new(cached, & &1.sample_id)

    # Separate cached and needs-computation
    {cached_samples, compute_samples} =
      Enum.split_with(samples, fn s -> MapSet.member?(cached_ids, s.id) end)

    # Build results for cached
    cached_results =
      Enum.map(cached_samples, fn sample ->
        measurement = Enum.find(cached, &(&1.sample_id == sample.id))
        emit_measurement_telemetry(sample.id, key, 0, :cached)
        {:ok, :cached, measurement.value}
      end)

    # Compute remaining
    computed_results =
      if length(compute_samples) > 0 do
        if Measurement.batch_capable?(measurement_module) do
          compute_batch_measurements(compute_samples, measurement_module, key, version, opts)
        else
          compute_individual_measurements(compute_samples, measurement_module, key, version, opts)
        end
      else
        []
      end

    # Combine and return in original order
    result_map =
      (cached_results ++ computed_results)
      |> Enum.zip(cached_samples ++ compute_samples)
      |> Enum.into(%{}, fn {result, sample} -> {sample.id, result} end)

    Enum.map(sample_ids, fn id -> Map.get(result_map, id, {:error, :sample_not_found}) end)
  end

  @doc """
  Computes measurements asynchronously using Task.Supervisor.

  Returns a Task that can be awaited for results.
  """
  def measure_async(sample_ids, measurement_module, opts \\ []) do
    Task.Supervisor.async(Forge.MeasurementTaskSupervisor, fn ->
      measure_batch(sample_ids, measurement_module, opts)
    end)
  end

  @doc """
  Computes a measurement after ensuring all dependencies are computed.

  Performs topological sort of dependencies and computes them in order.

  Returns same result format as measure_sample/3.
  """
  def measure_with_dependencies(sample_id, measurement_module, opts \\ []) do
    case resolve_dependencies([measurement_module]) do
      {:ok, ordered_modules} ->
        # Compute each dependency in order
        Enum.each(ordered_modules, fn mod ->
          # Don't fail if dependency already cached
          measure_sample(sample_id, mod, opts)
        end)

        # Compute the target measurement
        measure_sample(sample_id, measurement_module, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves a measurement from storage.

  Options:
  - `:version` - Specific version to retrieve (default: latest)
  """
  def get_measurement(sample_id, measurement_key, opts \\ []) do
    version = Keyword.get(opts, :version)

    query =
      if version do
        from(m in MeasurementRecord,
          where:
            m.sample_id == ^sample_id and
              m.measurement_key == ^measurement_key and
              m.measurement_version == ^version
        )
      else
        from(m in MeasurementRecord,
          where: m.sample_id == ^sample_id and m.measurement_key == ^measurement_key,
          order_by: [desc: m.measurement_version],
          limit: 1
        )
      end

    case Repo.one(query) do
      nil -> {:error, :not_found}
      measurement -> {:ok, measurement}
    end
  end

  # Private functions

  defp compute_and_store_measurement(sample_id, measurement_module, key, version, _opts) do
    start_time = System.monotonic_time()

    Telemetry.measurement_start(sample_id, key, version)

    # Fetch sample
    sample = Repo.get!(Sample, sample_id)

    # Compute measurement
    case measurement_module.compute([sample]) do
      {:ok, value} ->
        # Store in database
        %MeasurementRecord{}
        |> MeasurementRecord.changeset(%{
          sample_id: sample_id,
          measurement_key: key,
          measurement_version: version,
          value: value,
          computed_at: DateTime.utc_now()
        })
        |> Repo.insert!(on_conflict: :nothing)

        duration = System.monotonic_time() - start_time
        Telemetry.measurement_stop(sample_id, key, duration, :computed)

        {:ok, :computed, value}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_batch_measurements(samples, measurement_module, key, version, opts) do
    batch_size = Keyword.get(opts, :batch_size, Measurement.batch_size(measurement_module))

    start_time = System.monotonic_time()

    results =
      samples
      |> Enum.chunk_every(batch_size)
      |> Enum.flat_map(fn batch ->
        case measurement_module.compute_batch(batch) do
          {:ok, results_list} ->
            # Store each result
            Enum.map(results_list, fn {sample_id, value} ->
              %MeasurementRecord{}
              |> MeasurementRecord.changeset(%{
                sample_id: sample_id,
                measurement_key: key,
                measurement_version: version,
                value: value,
                computed_at: DateTime.utc_now()
              })
              |> Repo.insert!(on_conflict: :nothing)

              {:ok, :computed, value}
            end)

          results_list when is_list(results_list) ->
            # Handle legacy case where compute_batch returns plain list instead of {:ok, list}
            # Store each result
            Enum.map(results_list, fn {sample_id, value} ->
              %MeasurementRecord{}
              |> MeasurementRecord.changeset(%{
                sample_id: sample_id,
                measurement_key: key,
                measurement_version: version,
                value: value,
                computed_at: DateTime.utc_now()
              })
              |> Repo.insert!(on_conflict: :nothing)

              {:ok, :computed, value}
            end)

          {:error, reason} ->
            Enum.map(batch, fn _ -> {:error, reason} end)
        end
      end)

    duration = System.monotonic_time() - start_time
    Telemetry.measurement_batch_complete(key, duration, length(results))

    results
  end

  defp compute_individual_measurements(samples, measurement_module, key, version, opts) do
    Enum.map(samples, fn sample ->
      case compute_and_store_measurement(sample.id, measurement_module, key, version, opts) do
        {:ok, status, value} -> {:ok, status, value}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp get_samples_by_ids(sample_ids) do
    Repo.all(from(s in Sample, where: s.id in ^sample_ids))
  end

  defp get_measurements_batch(sample_ids, key, version) do
    Repo.all(
      from(m in MeasurementRecord,
        where:
          m.sample_id in ^sample_ids and
            m.measurement_key == ^key and
            m.measurement_version == ^version
      )
    )
  end

  defp emit_measurement_telemetry(sample_id, key, duration, outcome) do
    Telemetry.measurement_stop(sample_id, key, duration, outcome)
  end

  @spec resolve_dependencies([module()]) ::
          {:ok, [module()]} | {:error, :circular_dependency}
  defp resolve_dependencies(modules) do
    do_resolve_dependencies(modules, [], [])
  end

  @spec do_resolve_dependencies([module()], [module()], [module()]) ::
          {:ok, [module()]} | {:error, :circular_dependency}
  defp do_resolve_dependencies([], _visited, ordered), do: {:ok, Enum.reverse(ordered)}

  defp do_resolve_dependencies([module | rest], visited, ordered) do
    cond do
      module in visited ->
        # Already processed or circular dependency
        if module in ordered do
          do_resolve_dependencies(rest, visited, ordered)
        else
          {:error, :circular_dependency}
        end

      true ->
        deps = Measurement.dependencies(module)
        visited = [module | visited]

        # Check for immediate circular dependency
        if module in deps do
          {:error, :circular_dependency}
        else
          # Recursively resolve dependencies
          case do_resolve_dependencies(deps, visited, ordered) do
            {:ok, ordered} ->
              # Add current module after its dependencies
              ordered = if module in ordered, do: ordered, else: ordered ++ [module]
              do_resolve_dependencies(rest, visited, ordered)

            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  end
end
