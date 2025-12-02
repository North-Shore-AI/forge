defmodule Forge.AnvilBridge.Direct do
  @moduledoc """
  Direct Elixir adapter for AnvilBridge - in-process integration.

  This adapter makes direct function calls to the Anvil application when
  Forge and Anvil are deployed together in the same Erlang VM (same cluster).

  ## Benefits

  - Zero network latency
  - Type-safe function calls
  - Shared transactions possible
  - No serialization overhead

  ## Usage

  Configure in `config/config.exs`:

      config :forge, :anvil_bridge_adapter, Forge.AnvilBridge.Direct

  ## Implementation Notes

  When Anvil modules are available, this adapter will:
  - Call Anvil.Queue.enqueue/2 for sample publishing
  - Call Anvil.Annotations.list/1 for label retrieval
  - Handle errors and normalize them to standard bridge errors
  - Apply timeouts and retries for resilience

  Currently returns `:not_available` errors until Anvil integration is complete.
  """

  @behaviour Forge.AnvilBridge

  @impl true
  def publish_sample(_sample, _opts) do
    # TODO: Integrate with Anvil.Queue when available
    # queue = Keyword.fetch!(opts, :queue)
    # include_measurements = Keyword.get(opts, :include_measurements, true)
    #
    # dto = Forge.AnvilBridge.sample_to_dto(sample, include_measurements: include_measurements)
    #
    # case Anvil.Queue.enqueue(queue, dto) do
    #   {:ok, job_id} -> {:ok, job_id}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def publish_batch(_samples, _opts) do
    # TODO: Integrate with Anvil.Queue when available
    # queue = Keyword.fetch!(opts, :queue)
    # include_measurements = Keyword.get(opts, :include_measurements, true)
    #
    # dtos = Enum.map(samples, fn sample ->
    #   Forge.AnvilBridge.sample_to_dto(sample, include_measurements: include_measurements)
    # end)
    #
    # case Anvil.Queue.enqueue_batch(queue, dtos) do
    #   {:ok, count} -> {:ok, count}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def get_labels(_sample_id) do
    # TODO: Integrate with Anvil.Annotations when available
    # case Anvil.Annotations.list_for_sample(sample_id) do
    #   {:ok, []} -> {:error, :not_found}
    #   {:ok, annotations} -> {:ok, Enum.map(annotations, &to_label_map/1)}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def sync_labels(_sample_id, _opts) do
    # TODO: Integrate with Anvil.Annotations when available
    # case get_labels(sample_id) do
    #   {:ok, labels} ->
    #     # Store labels in Forge.Storage or Forge.Repo metadata
    #     Enum.each(labels, fn label ->
    #       Forge.Storage.insert_metadata(%{
    #         sample_id: sample_id,
    #         key: "anvil_label",
    #         value: label.label,
    #         value_type: "string"
    #       })
    #     end)
    #     {:ok, length(labels)}
    #
    #   {:error, :not_found} -> {:ok, 0}
    #   error -> error
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def create_queue_for_pipeline(_pipeline_id, _opts) do
    # TODO: Integrate with Anvil.Queue when available
    # queue_name = Keyword.get(opts, :queue_name, pipeline_id)
    # description = Keyword.get(opts, :description)
    # priority = Keyword.get(opts, :priority, "normal")
    #
    # case Anvil.Queue.create(queue_name, description: description, priority: priority) do
    #   {:ok, _queue} -> {:ok, queue_name}
    #   {:error, :already_exists} -> {:ok, queue_name}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def get_queue_stats(_queue_name) do
    # TODO: Integrate with Anvil.Queue when available
    # case Anvil.Queue.stats(queue_name) do
    #   {:ok, stats} ->
    #     {:ok, %{
    #       total: stats.total,
    #       completed: stats.completed,
    #       pending: stats.pending,
    #       in_progress: stats.in_progress
    #     }}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  # Private helpers for DTO translation (to be implemented when integrating)

  # defp to_label_map(%Anvil.Annotation{} = annotation) do
  #   %{
  #     label: annotation.label,
  #     annotator_id: annotation.annotator_id,
  #     confidence: annotation.confidence || 1.0,
  #     created_at: annotation.created_at
  #   }
  # end

  # defp normalize_error(:not_found), do: :not_found
  # defp normalize_error(:timeout), do: :timeout
  # defp normalize_error({:timeout, _}), do: :timeout
  # defp normalize_error(:unauthorized), do: :unauthorized
  # defp normalize_error(reason), do: {:unexpected, reason}
end
