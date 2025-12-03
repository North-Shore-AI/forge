defmodule Forge.API.V1RouterTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation
  import Plug.Test
  import Plug.Conn

  alias Forge.API.Router
  alias Forge.API.State
  alias LabelingIR.Dataset

  @opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Forge.Repo)
    :ok
  end

  test "creates and fetches SampleIR via /v1" do
    id = "sample-#{System.unique_integer([:positive])}"

    sample_body = %{
      "id" => id,
      "tenant_id" => "tenant_acme",
      "namespace" => "news",
      "pipeline_id" => "pipe1",
      "payload" => %{"headline" => "hi"},
      "artifacts" => [],
      "metadata" => %{"source" => "forge"},
      "lineage_ref" => %{"trace" => "s-abc"},
      "created_at" => "2025-01-01T00:00:00Z",
      "extra_field" => "ignored"
    }

    conn =
      conn(:post, "/v1/samples", Jason.encode!(sample_body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 201
    assert %{"id" => ^id} = Jason.decode!(conn.resp_body)

    conn =
      conn(:get, "/v1/samples/#{id}")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["tenant_id"] == "tenant_acme"
    assert body["namespace"] == "news"
    assert body["payload"] == %{"headline" => "hi"}
    refute Map.has_key?(body, "extra_field")
  end

  test "requires tenant header on write" do
    sample_body = %{
      "id" => "sample-missing-tenant-#{System.unique_integer([:positive])}",
      "pipeline_id" => "pipe1",
      "payload" => %{}
    }

    conn =
      conn(:post, "/v1/samples", Jason.encode!(sample_body))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 422
    assert %{"error" => "tenant_id_required"} = Jason.decode!(conn.resp_body)
  end

  test "rejects invalid timestamps" do
    sample_body = %{
      "id" => "sample-time",
      "tenant_id" => "tenant_acme",
      "pipeline_id" => "pipe1",
      "payload" => %{},
      "created_at" => "not-a-date"
    }

    conn =
      conn(:post, "/v1/samples", Jason.encode!(sample_body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 422
    assert %{"error" => "invalid_datetime"} = Jason.decode!(conn.resp_body)
  end

  test "enforces tenant isolation when fetching samples" do
    id = "sample-tenant-#{System.unique_integer([:positive])}"

    sample_body = %{
      id: id,
      tenant_id: "tenant_a",
      pipeline_id: "pipe1",
      payload: %{},
      created_at: DateTime.utc_now()
    }

    :ok = State.put_sample(struct(LabelingIR.Sample, sample_body))

    conn =
      conn(:get, "/v1/samples/#{id}")
      |> put_req_header("x-tenant-id", "tenant_b")
      |> Router.call(@opts)

    assert conn.status == 404
  end

  test "serves DatasetIR and slices" do
    dataset_id = "ds-#{System.unique_integer([:positive])}"
    sample_id = "sample-#{System.unique_integer([:positive])}"

    dataset = %Dataset{
      id: dataset_id,
      tenant_id: "tenant_acme",
      namespace: "news",
      version: "v1",
      slices: [
        %{name: "validation", sample_ids: [sample_id], filter: %{"topic" => "news"}}
      ],
      source_refs: [],
      metadata: %{"source" => "forge"},
      lineage_ref: %{trace: "ds-trace"},
      created_at: ~U[2025-01-04 00:00:00Z]
    }

    assert :ok = State.put_dataset(dataset)
    assert {:ok, %Dataset{}} = State.get_dataset(dataset_id, "tenant_acme")

    conn =
      conn(:get, "/v1/datasets/#{dataset_id}")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["id"] == dataset_id
    assert [%{"name" => "validation"}] = body["slices"]

    conn =
      conn(:get, "/v1/datasets/#{dataset_id}/slices/validation")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 200
    slice = Jason.decode!(conn.resp_body)
    assert slice["name"] == "validation"
    assert slice["sample_ids"] == [sample_id]
  end

  test "creates and fetches DatasetIR via /v1" do
    dataset_id = "ds-create-#{System.unique_integer([:positive])}"

    dataset_body = %{
      "id" => dataset_id,
      "tenant_id" => "tenant_acme",
      "namespace" => "news",
      "version" => "v2",
      "slices" => [%{"name" => "train", "sample_ids" => ["s1", "s2"]}],
      "metadata" => %{"source" => "forge"},
      "created_at" => "2025-01-05T00:00:00Z"
    }

    conn =
      conn(:post, "/v1/datasets", Jason.encode!(dataset_body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 201
    assert %{"id" => ^dataset_id} = Jason.decode!(conn.resp_body)

    # Ensure dataset persisted in the sandboxed repo
    assert {:ok, %Dataset{}} = State.get_dataset(dataset_id, "tenant_acme")

    conn =
      conn(:get, "/v1/datasets/#{dataset_id}")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["version"] == "v2"
    assert [%{"name" => "train", "sample_ids" => ["s1", "s2"]}] = body["slices"]

    conn =
      conn(:get, "/v1/datasets/#{dataset_id}/slices/train")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 200
    assert %{"name" => "train", "sample_ids" => ["s1", "s2"]} = Jason.decode!(conn.resp_body)

    conn =
      conn(:get, "/v1/datasets/#{dataset_id}/slices/missing")
      |> put_req_header("x-tenant-id", "tenant_acme")
      |> Router.call(@opts)

    assert conn.status == 404
  end
end
