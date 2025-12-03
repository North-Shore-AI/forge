defmodule Forge.API.Router do
  @moduledoc """
  Plug router exposing Forge `/v1` endpoints for SampleIR and DatasetIR.
  """

  use Plug.Router

  alias Forge.API.State
  alias LabelingIR.{Dataset, Sample}

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason,
    pass: ["application/json"]
  )

  plug(:dispatch)

  post "/v1/samples" do
    with {:ok, tenant} <- require_tenant(conn),
         :ok <- authorize_pipeline(conn),
         {:ok, sample} <- decode_sample(conn.body_params, tenant),
         :ok <- State.put_sample(sample) do
      send_json(conn, 201, sample)
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  get "/v1/samples/:id" do
    tenant = tenant_header(conn)

    case State.get_sample(id, tenant) do
      {:ok, sample} -> send_json(conn, 200, sample)
      :error -> send_resp(conn, 404, "")
    end
  end

  post "/v1/datasets" do
    with {:ok, tenant} <- require_tenant(conn),
         :ok <- authorize_pipeline(conn),
         {:ok, dataset} <- decode_dataset(conn.body_params, tenant),
         :ok <- State.put_dataset(dataset) do
      send_json(conn, 201, dataset)
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  get "/v1/datasets/:id" do
    tenant = tenant_header(conn)

    case State.get_dataset(id, tenant) do
      {:ok, dataset} -> send_json(conn, 200, dataset)
      :error -> send_resp(conn, 404, "")
    end
  end

  get "/v1/datasets/:id/slices/:name" do
    tenant = tenant_header(conn)

    case State.get_dataset_slice(id, name, tenant) do
      {:ok, slice} -> send_json(conn, 200, slice)
      :error -> send_resp(conn, 404, "")
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  ## Helpers

  defp require_tenant(conn) do
    case Plug.Conn.get_req_header(conn, "x-tenant-id") do
      [tenant | _] when is_binary(tenant) and tenant != "" -> {:ok, tenant}
      _ -> {:error, :tenant_required}
    end
  end

  defp tenant_header(conn) do
    case Plug.Conn.get_req_header(conn, "x-tenant-id") do
      [tenant | _] when is_binary(tenant) and tenant != "" -> tenant
      _ -> nil
    end
  end

  defp authorize_pipeline(conn) do
    # Stub hook for future auth/RBAC. For now, allow if tenant header is present.
    case Plug.Conn.get_req_header(conn, "authorization") do
      [_ | _] -> :ok
      _ -> :ok
    end
  end

  defp decode_sample(params, tenant) do
    with {:ok, created_at} <- parse_datetime(params["created_at"]) do
      {:ok,
       %Sample{
         id: params["id"] || Ecto.UUID.generate(),
         tenant_id: tenant,
         namespace: Map.get(params, "namespace"),
         pipeline_id: params["pipeline_id"],
         payload: Map.get(params, "payload", %{}),
         artifacts: Map.get(params, "artifacts", []),
         metadata: Map.get(params, "metadata", %{}),
         lineage_ref: Map.get(params, "lineage_ref"),
         created_at: created_at
       }}
    end
  end

  defp decode_dataset(params, tenant) do
    with {:ok, created_at} <- parse_datetime(params["created_at"]) do
      slices = Map.get(params, "slices", [])
      source_refs = Map.get(params, "source_refs", [])

      {:ok,
       %Dataset{
         id: params["id"] || Ecto.UUID.generate(),
         tenant_id: tenant,
         namespace: Map.get(params, "namespace"),
         version: params["version"] || "v1",
         slices: slices,
         source_refs: source_refs,
         metadata: Map.get(params, "metadata", %{}),
         lineage_ref: Map.get(params, "lineage_ref"),
         created_at: created_at
       }}
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}

  defp parse_datetime(nil), do: {:ok, DateTime.utc_now()}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(value), do: {:ok, value}

  defp send_json(conn, status, %Dataset{} = dataset) do
    send_json(conn, status, Map.from_struct(dataset))
  end

  defp send_json(conn, status, data) do
    body = Jason.encode!(data)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_error(conn, :tenant_required),
    do: send_resp(conn, 422, Jason.encode!(%{error: "tenant_id_required"}))

  defp send_error(conn, :invalid_datetime),
    do: send_resp(conn, 422, Jason.encode!(%{error: "invalid_datetime"}))
end
