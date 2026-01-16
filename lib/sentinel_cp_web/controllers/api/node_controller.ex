defmodule SentinelCpWeb.Api.NodeController do
  @moduledoc """
  API controller for node-facing endpoints.
  These endpoints are called by Sentinel nodes, not operators.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Nodes, Projects, Audit}

  @doc """
  POST /api/v1/projects/:project_slug/nodes/register

  Registers a new node. Returns the node_id and node_key.
  The node_key should be stored securely by the node.
  """
  def register(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- build_registration_attrs(params, project, conn),
         {:ok, node} <- Nodes.register_node(attrs) do
      Audit.log_system_action("node.registered", "node", node.id,
        project_id: project.id,
        metadata: %{name: node.name, ip: node.ip}
      )

      conn
      |> put_status(:created)
      |> json(%{
        node_id: node.id,
        node_key: node.node_key,
        poll_interval_s: 30
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/heartbeat

  Records a heartbeat from a node. Requires node authentication.
  """
  def heartbeat(conn, params) do
    node = conn.assigns.current_node

    attrs = %{
      health: params["health"] || %{},
      metrics: params["metrics"] || %{},
      active_bundle_id: params["active_bundle_id"],
      staged_bundle_id: params["staged_bundle_id"],
      version: params["version"],
      ip: params["ip"] || get_client_ip(conn),
      hostname: params["hostname"],
      metadata: params["metadata"] || %{}
    }

    case Nodes.record_heartbeat(node, attrs) do
      {:ok, updated_node} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "ok",
          node_id: updated_node.id,
          last_seen_at: updated_node.last_seen_at
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to record heartbeat: #{inspect(reason)}"})
    end
  end

  @doc """
  GET /api/v1/nodes/:node_id/bundles/latest

  Returns the latest bundle assignment for a node.
  Requires node authentication.
  """
  def latest_bundle(conn, _params) do
    _node = conn.assigns.current_node

    # TODO: Return bundle assignment when bundles are implemented
    conn
    |> put_status(:ok)
    |> json(%{
      no_update: true,
      poll_after_s: 30
    })
  end

  # Private helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp build_registration_attrs(params, project, conn) do
    %{
      project_id: project.id,
      name: params["name"],
      labels: params["labels"] || %{},
      capabilities: params["capabilities"] || [],
      version: params["version"],
      ip: params["ip"] || get_client_ip(conn),
      hostname: params["hostname"],
      metadata: params["metadata"] || %{}
    }
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
