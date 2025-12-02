defmodule Forge.AnvilBridge do
  @moduledoc """
  Behaviour for Anvil integration - publishing samples to Anvil for labeling.

  Anvil is North-Shore-AI's human-in-the-loop labeling platform. This bridge
  enables Forge to export samples to Anvil queues and sync labels back.

  ## Callbacks

  - `publish_sample/2` - Publish a single sample to Anvil
  - `publish_batch/2` - Batch publish samples to Anvil
  - `get_labels/1` - Fetch labels for a sample from Anvil
  - `sync_labels/2` - Bidirectional label sync
  - `create_queue_for_pipeline/2` - Create Anvil queue for pipeline samples
  - `get_queue_stats/1` - Fetch queue statistics

  ## Adapters

  - `Mock` - Test adapter with in-memory state
  - `Direct` - Direct Elixir calls (same BEAM cluster)
  - `HTTP` - REST API calls (separate deployment)

  ## Configuration

      # config/config.exs
      config :forge, :anvil_bridge_adapter, Forge.AnvilBridge.Direct

  ## Examples

      # Publish a sample
      adapter = Application.get_env(:forge, :anvil_bridge_adapter)
      {:ok, job_id} = adapter.publish_sample(sample, queue: "cns_narratives")

      # Batch publish
      {:ok, count} = adapter.publish_batch(samples, queue: "cns_narratives")

      # Get labels
      {:ok, labels} = adapter.get_labels(sample_id)
  """

  @type sample_id :: String.t()
  @type job_id :: String.t()
  @type queue_name :: String.t()
  @type error ::
          :not_found
          | :timeout
          | :network
          | :unauthorized
          | :not_available
          | {:unexpected, term()}

  @doc """
  Publish a single sample to Anvil labeling queue.

  ## Parameters

    * `sample` - The Forge sample to publish
    * `opts` - Options including:
      * `:queue` - Target Anvil queue name (required)
      * `:include_measurements` - Include measurements in metadata (default: true)

  ## Returns

    * `{:ok, job_id}` - Success with Anvil labeling job ID
    * `{:error, reason}` - Failure

  ## Examples

      sample = %Forge.Sample{id: "abc-123", data: %{"claim" => "Earth orbits Sun"}}
      {:ok, job_id} = adapter.publish_sample(sample, queue: "cns_narratives")
  """
  @callback publish_sample(sample :: map(), opts :: keyword()) ::
              {:ok, job_id()} | {:error, error()}

  @doc """
  Batch publish samples to Anvil labeling queue.

  More efficient than multiple `publish_sample/2` calls.

  ## Parameters

    * `samples` - List of Forge samples
    * `opts` - Options (same as `publish_sample/2`)

  ## Returns

    * `{:ok, count}` - Number of samples published
    * `{:error, reason}` - Failure

  ## Examples

      {:ok, 100} = adapter.publish_batch(samples, queue: "cns_narratives")
  """
  @callback publish_batch(samples :: [map()], opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Fetch labels for a sample from Anvil.

  ## Parameters

    * `sample_id` - Forge sample UUID

  ## Returns

    * `{:ok, labels}` - List of label maps with keys:
      * `:label` - The label value (e.g., "entailment", "neutral")
      * `:annotator_id` - UUID of the annotator
      * `:confidence` - Confidence score (0.0-1.0)
      * `:created_at` - Timestamp of annotation
    * `{:error, :not_found}` - Sample has no labels
    * `{:error, reason}` - Other failures

  ## Examples

      {:ok, labels} = adapter.get_labels("sample-123")
      # [%{label: "entailment", annotator_id: "user-1", confidence: 1.0, ...}]
  """
  @callback get_labels(sample_id()) ::
              {:ok, [map()]} | {:error, error()}

  @doc """
  Sync labels from Anvil back to Forge sample metadata.

  This is typically called after labeling is complete to enrich
  Forge samples with human annotations.

  ## Parameters

    * `sample_id` - Forge sample UUID
    * `opts` - Options including:
      * `:force` - Re-sync even if labels already exist (default: false)

  ## Returns

    * `{:ok, count}` - Number of labels synced
    * `{:error, reason}` - Failure

  ## Examples

      {:ok, 3} = adapter.sync_labels("sample-123")
  """
  @callback sync_labels(sample_id(), opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Create an Anvil queue for pipeline samples.

  ## Parameters

    * `pipeline_id` - Forge pipeline UUID
    * `opts` - Options including:
      * `:queue_name` - Custom queue name (default: pipeline_id)
      * `:description` - Queue description
      * `:priority` - Queue priority (default: "normal")

  ## Returns

    * `{:ok, queue_name}` - Created queue name
    * `{:error, reason}` - Failure

  ## Examples

      {:ok, "pipeline-abc-123"} = adapter.create_queue_for_pipeline(
        "pipeline-abc-123",
        description: "CNS narrative samples"
      )
  """
  @callback create_queue_for_pipeline(pipeline_id :: String.t(), opts :: keyword()) ::
              {:ok, queue_name()} | {:error, error()}

  @doc """
  Fetch queue statistics from Anvil.

  ## Parameters

    * `queue_name` - Anvil queue name

  ## Returns

    * `{:ok, stats}` - Map with keys:
      * `:total` - Total samples in queue
      * `:completed` - Completed samples
      * `:pending` - Pending samples
      * `:in_progress` - Samples being labeled
    * `{:error, reason}` - Failure

  ## Examples

      {:ok, stats} = adapter.get_queue_stats("cns_narratives")
      # %{total: 500, completed: 47, pending: 450, in_progress: 3}
  """
  @callback get_queue_stats(queue_name()) ::
              {:ok, map()} | {:error, error()}

  # Public API - delegates to configured adapter

  @doc """
  Publish a sample to Anvil labeling queue.

  Delegates to the configured adapter.
  """
  def publish_sample(sample, opts \\ []), do: adapter().publish_sample(sample, opts)

  @doc """
  Batch publish samples to Anvil labeling queue.

  Delegates to the configured adapter.
  """
  def publish_batch(samples, opts \\ []), do: adapter().publish_batch(samples, opts)

  @doc """
  Fetch labels for a sample from Anvil.

  Delegates to the configured adapter.
  """
  def get_labels(sample_id), do: adapter().get_labels(sample_id)

  @doc """
  Sync labels from Anvil back to Forge sample metadata.

  Delegates to the configured adapter.
  """
  def sync_labels(sample_id, opts \\ []), do: adapter().sync_labels(sample_id, opts)

  @doc """
  Create an Anvil queue for pipeline samples.

  Delegates to the configured adapter.
  """
  def create_queue_for_pipeline(pipeline_id, opts \\ []),
    do: adapter().create_queue_for_pipeline(pipeline_id, opts)

  @doc """
  Fetch queue statistics from Anvil.

  Delegates to the configured adapter.
  """
  def get_queue_stats(queue_name), do: adapter().get_queue_stats(queue_name)

  # Private helpers

  defp adapter do
    Application.get_env(:forge, :anvil_bridge_adapter, Forge.AnvilBridge.Mock)
  end

  @doc """
  Convert a Forge sample to Anvil-ready DTO format.

  ## Parameters

    * `sample` - Forge sample map/struct
    * `opts` - Options including:
      * `:include_measurements` - Include measurements in metadata (default: true)

  ## Returns

    Map with keys: `:sample_id`, `:title`, `:body`, `:metadata`

  ## Examples

      dto = Forge.AnvilBridge.sample_to_dto(sample, include_measurements: true)
      # %{
      #   sample_id: "abc-123",
      #   title: "Claim: Earth orbits Sun",
      #   body: "Narrative A: ...\nNarrative B: ...",
      #   metadata: %{pipeline_id: "...", measurements: %{...}}
      # }
  """
  def sample_to_dto(sample, opts \\ []) do
    include_measurements = Keyword.get(opts, :include_measurements, true)

    sample_data = sample[:data] || sample.data || %{}
    sample_id = sample[:id] || sample.id
    pipeline_id = sample[:pipeline_id] || Map.get(sample, :pipeline_id)

    measurements =
      if include_measurements do
        sample[:measurements] || Map.get(sample, :measurements, %{})
      else
        %{}
      end

    %{
      sample_id: sample_id,
      title: extract_title(sample_data),
      body: extract_body(sample_data),
      metadata: %{
        pipeline_id: pipeline_id,
        measurements: measurements,
        source_data: sample_data
      }
    }
  end

  # Extract title from sample data
  defp extract_title(data) when is_map(data) do
    cond do
      Map.has_key?(data, "title") -> data["title"]
      Map.has_key?(data, :title) -> data.title
      Map.has_key?(data, "claim") -> "Claim: #{String.slice(data["claim"], 0..50)}..."
      Map.has_key?(data, :claim) -> "Claim: #{String.slice(data.claim, 0..50)}..."
      true -> "Sample"
    end
  end

  defp extract_title(_), do: "Sample"

  # Extract body from sample data
  defp extract_body(data) when is_map(data) do
    cond do
      Map.has_key?(data, "text") ->
        data["text"]

      Map.has_key?(data, :text) ->
        data.text

      Map.has_key?(data, "narrative") ->
        data["narrative"]

      Map.has_key?(data, :narrative) ->
        data.narrative

      Map.has_key?(data, "narrative_a") and Map.has_key?(data, "narrative_b") ->
        "Narrative A: #{data["narrative_a"]}\n\nNarrative B: #{data["narrative_b"]}"

      Map.has_key?(data, :narrative_a) and Map.has_key?(data, :narrative_b) ->
        "Narrative A: #{data.narrative_a}\n\nNarrative B: #{data.narrative_b}"

      true ->
        Jason.encode!(data)
    end
  end

  defp extract_body(data), do: inspect(data)
end
