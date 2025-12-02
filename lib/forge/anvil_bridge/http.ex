defmodule Forge.AnvilBridge.HTTP do
  @moduledoc """
  HTTP adapter for AnvilBridge - REST API integration.

  This adapter makes HTTP API calls to Anvil when Forge and Anvil are
  deployed as separate services (different hosts/containers).

  ## Benefits

  - Service isolation (deploy independently)
  - Language-agnostic integration
  - Horizontal scaling of Forge and Anvil
  - Clear API boundaries

  ## Configuration

      config :forge, :anvil_bridge_adapter, Forge.AnvilBridge.HTTP
      config :forge, :anvil_api_url, "https://anvil.example.com"
      config :forge, :anvil_api_key, System.get_env("ANVIL_API_KEY")

  ## API Endpoints

  - POST /api/v1/samples/publish - Publish sample to queue
  - POST /api/v1/samples/batch - Batch publish samples
  - GET /api/v1/samples/:id/labels - Get labels for sample
  - POST /api/v1/samples/:id/sync_labels - Sync labels to Forge
  - POST /api/v1/queues - Create queue
  - GET /api/v1/queues/:name/stats - Get queue statistics

  ## Implementation Notes

  Currently returns `:not_available` errors until Anvil HTTP API is implemented.
  When available, this adapter will:
  - Use HTTPoison or Req for HTTP requests
  - Handle authentication with API keys
  - Apply timeouts and retries
  - Parse JSON responses
  """

  @behaviour Forge.AnvilBridge

  # TODO: Add timeout and retry configuration when HTTP implementation is complete
  # @default_timeout 30_000
  # @default_retries 3

  @impl true
  def publish_sample(_sample, _opts) do
    # TODO: Implement HTTP API call
    # queue = Keyword.fetch!(opts, :queue)
    # include_measurements = Keyword.get(opts, :include_measurements, true)
    #
    # dto = Forge.AnvilBridge.sample_to_dto(sample, include_measurements: include_measurements)
    # url = "#{api_url()}/api/v1/samples/publish"
    # headers = [{"Authorization", "Bearer #{api_key()}"}, {"Content-Type", "application/json"}]
    # body = Jason.encode!(%{queue: queue, sample: dto})
    #
    # case http_client().post(url, body, headers, timeout: @default_timeout, retry: @default_retries) do
    #   {:ok, %{status_code: 200, body: response_body}} ->
    #     %{"job_id" => job_id} = Jason.decode!(response_body)
    #     {:ok, job_id}
    #
    #   {:ok, %{status_code: 404}} ->
    #     {:error, :not_found}
    #
    #   {:ok, %{status_code: 401}} ->
    #     {:error, :unauthorized}
    #
    #   {:ok, %{status_code: status}} ->
    #     {:error, {:unexpected, {:http_error, status}}}
    #
    #   {:error, %{reason: :timeout}} ->
    #     {:error, :timeout}
    #
    #   {:error, %{reason: reason}} ->
    #     {:error, :network}
    # end
    {:error, :not_available}
  end

  @impl true
  def publish_batch(_samples, _opts) do
    # TODO: Implement HTTP API call
    # queue = Keyword.fetch!(opts, :queue)
    # include_measurements = Keyword.get(opts, :include_measurements, true)
    #
    # dtos = Enum.map(samples, fn sample ->
    #   Forge.AnvilBridge.sample_to_dto(sample, include_measurements: include_measurements)
    # end)
    #
    # url = "#{api_url()}/api/v1/samples/batch"
    # headers = [{"Authorization", "Bearer #{api_key()}"}, {"Content-Type", "application/json"}]
    # body = Jason.encode!(%{queue: queue, samples: dtos})
    #
    # case http_client().post(url, body, headers, timeout: @default_timeout, retry: @default_retries) do
    #   {:ok, %{status_code: 200, body: response_body}} ->
    #     %{"count" => count} = Jason.decode!(response_body)
    #     {:ok, count}
    #
    #   {:ok, %{status_code: 401}} ->
    #     {:error, :unauthorized}
    #
    #   {:ok, %{status_code: status}} ->
    #     {:error, {:unexpected, {:http_error, status}}}
    #
    #   {:error, %{reason: :timeout}} ->
    #     {:error, :timeout}
    #
    #   {:error, _} ->
    #     {:error, :network}
    # end
    {:error, :not_available}
  end

  @impl true
  def get_labels(_sample_id) do
    # TODO: Implement HTTP API call
    # url = "#{api_url()}/api/v1/samples/#{sample_id}/labels"
    # headers = [{"Authorization", "Bearer #{api_key()}"}]
    #
    # case http_client().get(url, headers, timeout: @default_timeout) do
    #   {:ok, %{status_code: 200, body: response_body}} ->
    #     %{"labels" => labels} = Jason.decode!(response_body)
    #     {:ok, labels}
    #
    #   {:ok, %{status_code: 404}} ->
    #     {:error, :not_found}
    #
    #   {:ok, %{status_code: 401}} ->
    #     {:error, :unauthorized}
    #
    #   {:ok, %{status_code: status}} ->
    #     {:error, {:unexpected, {:http_error, status}}}
    #
    #   {:error, %{reason: :timeout}} ->
    #     {:error, :timeout}
    #
    #   {:error, _} ->
    #     {:error, :network}
    # end
    {:error, :not_available}
  end

  @impl true
  def sync_labels(_sample_id, _opts) do
    # TODO: Implement HTTP API call
    # url = "#{api_url()}/api/v1/samples/#{sample_id}/sync_labels"
    # headers = [{"Authorization", "Bearer #{api_key()}"}, {"Content-Type", "application/json"}]
    # body = Jason.encode!(%{force: Keyword.get(opts, :force, false)})
    #
    # case http_client().post(url, body, headers, timeout: @default_timeout) do
    #   {:ok, %{status_code: 200, body: response_body}} ->
    #     %{"count" => count} = Jason.decode!(response_body)
    #     {:ok, count}
    #
    #   {:ok, %{status_code: 404}} ->
    #     {:error, :not_found}
    #
    #   {:ok, %{status_code: 401}} ->
    #     {:error, :unauthorized}
    #
    #   {:ok, %{status_code: status}} ->
    #     {:error, {:unexpected, {:http_error, status}}}
    #
    #   {:error, %{reason: :timeout}} ->
    #     {:error, :timeout}
    #
    #   {:error, _} ->
    #     {:error, :network}
    # end
    {:error, :not_available}
  end

  @impl true
  def create_queue_for_pipeline(_pipeline_id, _opts) do
    # TODO: Implement HTTP API call
    # queue_name = Keyword.get(opts, :queue_name, pipeline_id)
    # description = Keyword.get(opts, :description)
    # priority = Keyword.get(opts, :priority, "normal")
    #
    # url = "#{api_url()}/api/v1/queues"
    # headers = [{"Authorization", "Bearer #{api_key()}"}, {"Content-Type", "application/json"}]
    # body = Jason.encode!(%{
    #   name: queue_name,
    #   pipeline_id: pipeline_id,
    #   description: description,
    #   priority: priority
    # })
    #
    # case http_client().post(url, body, headers, timeout: @default_timeout) do
    #   {:ok, %{status_code: status}} when status in [200, 201] ->
    #     {:ok, queue_name}
    #
    #   {:ok, %{status_code: 401}} ->
    #     {:error, :unauthorized}
    #
    #   {:ok, %{status_code: status}} ->
    #     {:error, {:unexpected, {:http_error, status}}}
    #
    #   {:error, %{reason: :timeout}} ->
    #     {:error, :timeout}
    #
    #   {:error, _} ->
    #     {:error, :network}
    # end
    {:error, :not_available}
  end

  @impl true
  def get_queue_stats(_queue_name) do
    # TODO: Implement HTTP API call
    # url = "#{api_url()}/api/v1/queues/#{queue_name}/stats"
    # headers = [{"Authorization", "Bearer #{api_key()}"}]
    #
    # case http_client().get(url, headers, timeout: @default_timeout) do
    #   {:ok, %{status_code: 200, body: response_body}} ->
    #     stats = Jason.decode!(response_body)
    #     {:ok, %{
    #       total: stats["total"],
    #       completed: stats["completed"],
    #       pending: stats["pending"],
    #       in_progress: stats["in_progress"]
    #     }}
    #
    #   {:ok, %{status_code: 404}} ->
    #     {:error, :not_found}
    #
    #   {:ok, %{status_code: 401}} ->
    #     {:error, :unauthorized}
    #
    #   {:ok, %{status_code: status}} ->
    #     {:error, {:unexpected, {:http_error, status}}}
    #
    #   {:error, %{reason: :timeout}} ->
    #     {:error, :timeout}
    #
    #   {:error, _} ->
    #     {:error, :network}
    # end
    {:error, :not_available}
  end

  # Private helpers

  # defp api_url do
  #   Application.get_env(:forge, :anvil_api_url) ||
  #     raise "Missing :anvil_api_url config for Forge.AnvilBridge.HTTP"
  # end

  # defp api_key do
  #   Application.get_env(:forge, :anvil_api_key) ||
  #     raise "Missing :anvil_api_key config for Forge.AnvilBridge.HTTP"
  # end

  # defp http_client do
  #   Application.get_env(:forge, :http_client, HTTPoison)
  # end
end
