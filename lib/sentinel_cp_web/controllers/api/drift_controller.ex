defmodule SentinelCpWeb.Api.DriftController do
  @moduledoc """
  API controller for drift event management.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Nodes, Projects, Audit}

  @doc """
  GET /api/v1/projects/:project_slug/drift
  Lists drift events for a project.
  """
  def index(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      opts =
        [limit: parse_int(params["limit"], 100)]
        |> maybe_add_status_filter(params["status"])

      events = Nodes.list_drift_events(project.id, opts)

      conn
      |> put_status(:ok)
      |> json(%{
        drift_events: Enum.map(events, &drift_event_to_json/1),
        total: length(events)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/drift/stats
  Returns drift statistics for a project.
  """
  def stats(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      drift_stats = Nodes.get_drift_stats(project.id)
      event_stats = Nodes.get_drift_event_stats(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        total_managed: drift_stats.total_managed,
        drifted: drift_stats.drifted,
        in_sync: drift_stats.in_sync,
        active_events: event_stats.active,
        resolved_today: event_stats.resolved_today
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/drift/:id
  Shows a single drift event.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => event_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, event} <- get_drift_event(event_id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{drift_event: drift_event_to_json(event)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :drift_event_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Drift event not found"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/drift/:id/resolve
  Manually resolves a drift event.
  """
  def resolve(conn, %{"project_slug" => project_slug, "id" => event_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, event} <- get_drift_event(event_id, project.id),
         :ok <- check_not_resolved(event),
         {:ok, updated} <- Nodes.resolve_drift_event(event, "manual") do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "drift.resolved", "drift_event", event.id,
        project_id: project.id,
        changes: %{resolution: "manual"}
      )

      conn
      |> put_status(:ok)
      |> json(%{drift_event: drift_event_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :drift_event_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Drift event not found"})

      {:error, :already_resolved} ->
        conn |> put_status(:conflict) |> json(%{error: "Drift event already resolved"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/drift/resolve-all
  Resolves all active drift events for a project.
  """
  def resolve_all(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      events = Nodes.list_drift_events(project.id, include_resolved: false)

      resolved_count =
        Enum.reduce(events, 0, fn event, count ->
          case Nodes.resolve_drift_event(event, "manual") do
            {:ok, _} -> count + 1
            _ -> count
          end
        end)

      api_key = conn.assigns.current_api_key

      if resolved_count > 0 do
        Audit.log_api_key_action(api_key, "drift.bulk_resolved", "project", project.id,
          project_id: project.id,
          changes: %{resolved_count: resolved_count}
        )
      end

      conn
      |> put_status(:ok)
      |> json(%{resolved_count: resolved_count})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_drift_event(id, project_id) do
    case Nodes.get_drift_event(id) do
      nil -> {:error, :drift_event_not_found}
      %{project_id: ^project_id} = event -> {:ok, event}
      _ -> {:error, :drift_event_not_found}
    end
  end

  defp check_not_resolved(%{resolved_at: nil}), do: :ok
  defp check_not_resolved(_), do: {:error, :already_resolved}

  defp maybe_add_status_filter(opts, "active"), do: [{:include_resolved, false} | opts]
  defp maybe_add_status_filter(opts, _), do: [{:include_resolved, true} | opts]

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(val, _default) when is_integer(val), do: val

  defp drift_event_to_json(event) do
    %{
      id: event.id,
      node_id: event.node_id,
      project_id: event.project_id,
      expected_bundle_id: event.expected_bundle_id,
      actual_bundle_id: event.actual_bundle_id,
      detected_at: event.detected_at,
      resolved_at: event.resolved_at,
      resolution: event.resolution,
      inserted_at: event.inserted_at,
      updated_at: event.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
