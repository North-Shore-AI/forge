defmodule Forge.API.State do
  @moduledoc """
  Repo-backed storage for the Forge `/v1` IR API.
  """

  alias Forge.API.{DatasetRecord, SampleRecord}
  alias Forge.Repo
  alias LabelingIR.{Dataset, Sample}

  @spec reset!() :: :ok
  def reset! do
    Repo.transaction(fn ->
      Repo.delete_all(DatasetRecord)
      Repo.delete_all(SampleRecord)
    end)

    :ok
  end

  @spec put_sample(Sample.t()) :: :ok | {:error, term()}
  def put_sample(%Sample{} = sample) do
    attrs = %{
      id: sample.id,
      tenant_id: sample.tenant_id,
      namespace: sample.namespace,
      pipeline_id: sample.pipeline_id,
      payload: sample.payload,
      artifacts: sample.artifacts || [],
      metadata: sample.metadata || %{},
      lineage_ref: sample.lineage_ref,
      created_at: normalize_datetime(sample.created_at)
    }

    %SampleRecord{}
    |> SampleRecord.changeset(attrs)
    |> upsert()
  end

  @spec get_sample(String.t(), String.t() | nil) :: {:ok, Sample.t()} | :error
  def get_sample(id, tenant_id \\ nil) do
    case Repo.get(SampleRecord, id) do
      %SampleRecord{tenant_id: ^tenant_id} = record when not is_nil(tenant_id) ->
        {:ok, decode_sample(record)}

      %SampleRecord{} = record when is_nil(tenant_id) ->
        {:ok, decode_sample(record)}

      %SampleRecord{} ->
        :error

      _ ->
        fallback_pipeline_sample(id, tenant_id)
    end
  end

  @spec put_dataset(Dataset.t()) :: :ok | {:error, term()}
  def put_dataset(%Dataset{} = dataset) do
    attrs = %{
      id: dataset.id,
      tenant_id: dataset.tenant_id,
      namespace: dataset.namespace,
      version: dataset.version,
      slices: dataset.slices || [],
      source_refs: dataset.source_refs || [],
      metadata: dataset.metadata || %{},
      lineage_ref: dataset.lineage_ref,
      created_at: normalize_datetime(dataset.created_at)
    }

    %DatasetRecord{}
    |> DatasetRecord.changeset(attrs)
    |> upsert()
  end

  @spec get_dataset(String.t(), String.t() | nil) :: {:ok, Dataset.t()} | :error
  def get_dataset(id, tenant_id \\ nil) do
    case Repo.get(DatasetRecord, id) do
      %DatasetRecord{tenant_id: ^tenant_id} = record when not is_nil(tenant_id) ->
        {:ok, decode_dataset(record)}

      %DatasetRecord{} = record when is_nil(tenant_id) ->
        {:ok, decode_dataset(record)}

      %DatasetRecord{} ->
        :error

      _ ->
        :error
    end
  end

  @spec get_dataset_slice(String.t(), String.t(), String.t() | nil) :: {:ok, map()} | :error
  def get_dataset_slice(id, slice_name, tenant_id \\ nil) do
    with {:ok, dataset} <- get_dataset(id, tenant_id),
         %{} = slice <- Enum.find(dataset.slices, &match_slice?(&1, slice_name)) do
      {:ok, slice}
    else
      _ -> :error
    end
  end

  ## Helpers

  defp decode_sample(%SampleRecord{} = record) do
    %Sample{
      id: record.id,
      tenant_id: record.tenant_id,
      namespace: record.namespace,
      pipeline_id: record.pipeline_id,
      payload: record.payload || %{},
      artifacts: record.artifacts || [],
      metadata: record.metadata || %{},
      lineage_ref: record.lineage_ref,
      created_at: record.created_at
    }
  end

  defp decode_dataset(%DatasetRecord{} = record) do
    %Dataset{
      id: record.id,
      tenant_id: record.tenant_id,
      namespace: record.namespace,
      version: record.version,
      slices: record.slices || [],
      source_refs: record.source_refs || [],
      metadata: record.metadata || %{},
      lineage_ref: record.lineage_ref,
      created_at: record.created_at
    }
  end

  defp match_slice?(slice, name) do
    Map.get(slice, :name) == name || Map.get(slice, "name") == name
  end

  defp normalize_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp normalize_datetime(%NaiveDateTime{} = ndt), do: ndt
  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(other), do: other

  defp upsert(changeset) do
    case Repo.insert(changeset,
           on_conflict: {:replace_all_except, [:id, :inserted_at]},
           conflict_target: :id
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp fallback_pipeline_sample(id, tenant_id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Repo.get(Forge.Schema.Sample, uuid) do
          nil ->
            :error

          pipeline_sample ->
            data = pipeline_sample.data || %{}
            tenant_from_data = Map.get(data, "tenant_id") || Map.get(data, :tenant_id)

            if tenant_id && tenant_from_data && tenant_id != tenant_from_data do
              :error
            else
              sample = %Sample{
                id: pipeline_sample.id,
                tenant_id: tenant_from_data || tenant_id,
                namespace: Map.get(data, "namespace") || Map.get(data, :namespace),
                pipeline_id: pipeline_sample.pipeline_id,
                payload: data,
                artifacts: [],
                metadata: %{
                  pipeline_status: pipeline_sample.status,
                  version: pipeline_sample.version
                },
                lineage_ref: nil,
                created_at: pipeline_sample.inserted_at
              }

              {:ok, sample}
            end
        end

      :error ->
        # Not a pipeline UUID, so no fallback available
        :error
    end
  end
end
