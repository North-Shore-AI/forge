defmodule Forge.Storage.Postgres do
  @moduledoc """
  PostgreSQL storage adapter for Forge samples.

  Implements durable, queryable storage with support for:
  - Sample versioning and lineage
  - Stage execution history
  - Measurement tracking
  - Artifact metadata storage

  ## Options

    * `:pipeline_name` - Name of the pipeline (required)
    * `:pipeline_manifest` - Pipeline manifest map (optional)
  """

  @behaviour Forge.Storage

  alias Forge.{Repo, Telemetry}
  alias Forge.Schema.{Pipeline, Sample, StageExecution, MeasurementRecord}

  require Logger

  defstruct [:pipeline_id, :pipeline_name]

  @impl true
  def init(opts) do
    pipeline_name = Keyword.fetch!(opts, :pipeline_name)
    manifest = Keyword.get(opts, :pipeline_manifest, %{})

    # Create or get pipeline record
    pipeline_id = get_or_create_pipeline(pipeline_name, manifest)

    {:ok, %__MODULE__{pipeline_id: pipeline_id, pipeline_name: pipeline_name}}
  end

  @impl true
  def store(samples, state) when is_list(samples) do
    try do
      # Store all samples and collect results
      results =
        Enum.map(samples, fn sample ->
          store_sample(sample, state.pipeline_id)
        end)

      # Check if any failed
      case Enum.find(results, fn
             {:error, _} -> true
             _ -> false
           end) do
        {:error, changeset} ->
          {:error, changeset}

        nil ->
          {:ok, state}
      end
    rescue
      e ->
        Logger.error("Failed to store samples: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl true
  def retrieve(sample_id, state) do
    case Repo.get(Sample, sample_id) do
      nil ->
        {:error, :not_found}

      db_sample ->
        sample = convert_to_forge_sample(db_sample)
        {:ok, sample, state}
    end
  end

  @impl true
  def list(filters, state) do
    query = build_query(filters, state)

    samples =
      query
      |> Repo.all()
      |> Enum.map(&convert_to_forge_sample/1)

    {:ok, samples, state}
  end

  @impl true
  def cleanup(_state) do
    :ok
  end

  # Private Functions

  defp get_or_create_pipeline(name, manifest) do
    manifest_hash = compute_manifest_hash(manifest)

    case Repo.get_by(Pipeline, name: to_string(name), manifest_hash: manifest_hash) do
      nil ->
        %Pipeline{}
        |> Pipeline.changeset(%{
          name: to_string(name),
          manifest_hash: manifest_hash,
          manifest: manifest,
          status: "pending"
        })
        |> Repo.insert!()
        |> Map.get(:id)

      pipeline ->
        pipeline.id
    end
  end

  defp compute_manifest_hash(manifest) when is_map(manifest) do
    manifest
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp compute_manifest_hash(_), do: "empty"

  defp store_sample(sample, pipeline_id) do
    # Map Forge.Sample status atoms to DB enum values
    db_status = map_status_to_db(sample.status)

    # Convert Forge.Sample to DB schema
    attrs = %{
      pipeline_id: pipeline_id,
      status: db_status,
      data: sample.data
    }

    # Use existing sample ID if provided, or let DB generate one
    changeset =
      if sample.id do
        # Preserve the sample ID
        Sample.changeset(%Sample{id: sample.id}, attrs)
      else
        Sample.changeset(%Sample{}, attrs)
      end

    # Measure storage timing and size
    start_time = System.monotonic_time()
    size_bytes = byte_size(:erlang.term_to_binary(sample.data))

    result = Repo.insert(changeset, on_conflict: :replace_all, conflict_target: :id)

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, db_sample} ->
        # Emit telemetry event
        Telemetry.storage_sample_write(
          sample.id || db_sample.id,
          duration,
          size_bytes,
          :postgres
        )

        # Store measurements if present
        store_measurements(sample, db_sample.id)
        {:ok, db_sample}

      {:error, changeset} ->
        Logger.error("Failed to store sample: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # Map Forge.Sample status atoms to DB enum values
  defp map_status_to_db(:pending), do: "pending"
  defp map_status_to_db(:measured), do: "processing"
  defp map_status_to_db(:ready), do: "completed"
  defp map_status_to_db(:labeled), do: "completed"
  defp map_status_to_db(:skipped), do: "failed"
  defp map_status_to_db(:completed), do: "completed"
  defp map_status_to_db(:processing), do: "processing"
  defp map_status_to_db(:failed), do: "failed"
  defp map_status_to_db(:dlq), do: "dlq"
  defp map_status_to_db(status) when is_binary(status), do: status
  defp map_status_to_db(status), do: to_string(status)

  defp store_measurements(sample, sample_id) do
    unless Enum.empty?(sample.measurements) do
      Enum.each(sample.measurements, fn {key, value} ->
        attrs = %{
          sample_id: sample_id,
          measurement_key: to_string(key),
          value: %{result: value},
          computed_at: sample.measured_at || DateTime.utc_now()
        }

        %MeasurementRecord{}
        |> MeasurementRecord.changeset(attrs)
        |> Repo.insert(
          on_conflict: :replace_all,
          conflict_target: [:sample_id, :measurement_key, :measurement_version]
        )
      end)
    end
  end

  defp convert_to_forge_sample(db_sample) do
    # Load measurements
    measurements =
      db_sample
      |> Repo.preload(:measurements)
      |> Map.get(:measurements, [])
      |> Enum.map(fn m -> {String.to_atom(m.measurement_key), m.value["result"]} end)
      |> Enum.into(%{})

    Forge.Sample.new(
      id: db_sample.id,
      pipeline: :postgres_loaded,
      data: db_sample.data,
      status: String.to_atom(db_sample.status),
      measurements: measurements,
      created_at: db_sample.inserted_at
    )
  end

  defp build_query(filters, state) do
    import Ecto.Query

    base_query = from(s in Sample, where: s.pipeline_id == ^state.pipeline_id)

    Enum.reduce(filters, base_query, fn
      {:status, status}, query ->
        from(s in query, where: s.status == ^to_string(status))

      {:after, datetime}, query ->
        from(s in query, where: s.inserted_at > ^datetime)

      {:before, datetime}, query ->
        from(s in query, where: s.inserted_at < ^datetime)

      _, query ->
        query
    end)
  end

  @doc """
  Records a stage execution for a sample.

  This is a helper function for tracking pipeline lineage.
  """
  def record_stage_execution(sample_id, stage_name, opts \\ []) do
    attrs = %{
      sample_id: sample_id,
      stage_name: to_string(stage_name),
      stage_config_hash: Keyword.get(opts, :config_hash, "default"),
      status: Keyword.get(opts, :status, "success"),
      error_message: Keyword.get(opts, :error_message),
      duration_ms: Keyword.get(opts, :duration_ms),
      applied_at: DateTime.utc_now()
    }

    %StageExecution{}
    |> StageExecution.changeset(attrs)
    |> Repo.insert()
  end
end
