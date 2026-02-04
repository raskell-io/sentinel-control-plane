defmodule SentinelCpWeb.NodesLive.Show do
  @moduledoc """
  LiveView for viewing node details.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Nodes, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => project_slug, "id" => node_id} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(project_slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Project not found") |> redirect(to: ~p"/")}

      project ->
        case Nodes.get_node(node_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Node not found")
             |> redirect(to: nodes_path(org, project))}

          %{project_id: pid} = node when pid == project.id ->
            if connected?(socket) do
              Phoenix.PubSub.subscribe(SentinelCp.PubSub, "nodes:#{project.id}:#{node.id}")
              :timer.send_interval(10_000, self(), :refresh)
            end

            heartbeats = Nodes.list_recent_heartbeats(node.id, limit: 20)

            {:ok,
             socket
             |> assign(:org, org)
             |> assign(:project, project)
             |> assign(:node, node)
             |> assign(:heartbeats, heartbeats)
             |> assign(:show_label_form, false)
             |> assign(:page_title, "#{node.name} - #{project.name}")}

          _ ->
            {:ok,
             socket
             |> put_flash(:error, "Node not found")
             |> redirect(to: nodes_path(org, project))}
        end
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp nodes_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes"

  defp nodes_path(nil, project),
    do: ~p"/projects/#{project.slug}/nodes"

  defp bundle_path(%{slug: org_slug}, project, bundle_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle_id}"

  defp bundle_path(nil, project, bundle_id),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle_id}"

  @impl true
  def handle_info(:refresh, socket) do
    node = Nodes.get_node!(socket.assigns.node.id)
    heartbeats = Nodes.list_recent_heartbeats(node.id, limit: 20)
    {:noreply, assign(socket, node: node, heartbeats: heartbeats)}
  end

  @impl true
  def handle_info({:node_updated, node}, socket) do
    heartbeats = Nodes.list_recent_heartbeats(node.id, limit: 20)
    {:noreply, assign(socket, node: node, heartbeats: heartbeats)}
  end

  @impl true
  def handle_event("delete", _, socket) do
    case Nodes.delete_node(socket.assigns.node) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "node", socket.assigns.node.id,
          project_id: socket.assigns.project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Node deleted")
         |> redirect(to: nodes_path(socket.assigns.org, socket.assigns.project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete node")}
    end
  end

  def handle_event("toggle_label_form", _, socket) do
    {:noreply, assign(socket, show_label_form: !socket.assigns.show_label_form)}
  end

  def handle_event("update_labels", %{"labels" => labels_str}, socket) do
    labels =
      labels_str
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
          _ -> acc
        end
      end)

    node = socket.assigns.node

    case Nodes.update_node_labels(node, labels) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update_labels", "node", node.id,
          project_id: socket.assigns.project.id
        )

        {:noreply,
         socket
         |> assign(node: updated, show_label_form: false)
         |> put_flash(:info, "Labels updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update labels.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="mb-6">
        <.link
          navigate={nodes_path(@org, @project)}
          class="text-sm text-gray-500 hover:text-gray-700"
        >
          &larr; Back to nodes
        </.link>
      </div>

      <div class="flex justify-between items-start mb-6">
        <div>
          <h1 class="text-2xl font-bold flex items-center gap-3">
            {@node.name}
            <.status_badge status={@node.status} />
          </h1>
          <p class="text-gray-500 mt-1">
            Registered {format_datetime(@node.registered_at)}
          </p>
        </div>
        <button
          phx-click="delete"
          data-confirm="Are you sure you want to delete this node?"
          class="btn btn-error btn-sm"
        >
          Delete Node
        </button>
      </div>

      <div class="grid grid-cols-2 gap-6">
        <!-- Node Info Card -->
        <div class="bg-base-100 rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">Node Information</h2>
          <dl class="space-y-3">
            <div class="flex justify-between">
              <dt class="text-gray-500">ID</dt>
              <dd class="font-mono text-sm">{@node.id}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">Hostname</dt>
              <dd class="font-mono text-sm">{@node.hostname || "-"}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">IP Address</dt>
              <dd class="font-mono text-sm">{@node.ip || "-"}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">Version</dt>
              <dd class="font-mono text-sm">{@node.version || "-"}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">Last Seen</dt>
              <dd class="text-sm">
                {if @node.last_seen_at, do: format_relative_time(@node.last_seen_at), else: "Never"}
              </dd>
            </div>
          </dl>
        </div>
        
    <!-- Bundle Status Card -->
        <div class="bg-base-100 rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">Bundle Status</h2>
          <dl class="space-y-3">
            <div class="flex justify-between">
              <dt class="text-gray-500">Active Bundle</dt>
              <dd class="font-mono text-sm">
                <%= if @node.active_bundle_id do %>
                  <.link
                    navigate={bundle_path(@org, @project, @node.active_bundle_id)}
                    class="link link-primary"
                  >
                    {String.slice(@node.active_bundle_id, 0, 8)}…
                  </.link>
                <% else %>
                  None
                <% end %>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">Staged Bundle</dt>
              <dd class="font-mono text-sm">
                <%= if @node.staged_bundle_id do %>
                  <.link
                    navigate={bundle_path(@org, @project, @node.staged_bundle_id)}
                    class="link link-primary"
                  >
                    {String.slice(@node.staged_bundle_id, 0, 8)}…
                  </.link>
                <% else %>
                  None
                <% end %>
              </dd>
            </div>
          </dl>
        </div>
        
    <!-- Labels Card -->
        <div class="bg-base-100 rounded-lg shadow p-6">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-lg font-semibold">Labels</h2>
            <button class="btn btn-ghost btn-xs" phx-click="toggle_label_form">
              Edit Labels
            </button>
          </div>
          <div :if={@show_label_form} class="mb-4">
            <form phx-submit="update_labels" class="space-y-3">
              <div class="form-control">
                <label class="label"><span class="label-text">Labels (one key=value per line)</span></label>
                <textarea
                  name="labels"
                  rows="5"
                  class="textarea textarea-bordered font-mono text-sm w-full"
                >{format_labels_for_edit(@node.labels)}</textarea>
              </div>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary btn-xs">Save</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="toggle_label_form">
                  Cancel
                </button>
              </div>
            </form>
          </div>
          <%= if @node.labels && map_size(@node.labels) > 0 do %>
            <div class="flex flex-wrap gap-2">
              <%= for {key, value} <- @node.labels do %>
                <span class="badge badge-outline">
                  {key}: {value}
                </span>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-500 text-sm">No labels</p>
          <% end %>
        </div>
        
    <!-- Capabilities Card -->
        <div class="bg-base-100 rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">Capabilities</h2>
          <%= if @node.capabilities && length(@node.capabilities) > 0 do %>
            <div class="flex flex-wrap gap-2">
              <%= for cap <- @node.capabilities do %>
                <span class="badge badge-primary badge-outline">{cap}</span>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-500 text-sm">No capabilities reported</p>
          <% end %>
        </div>
      </div>
      
    <!-- Recent Heartbeats -->
      <div class="mt-6 bg-base-100 rounded-lg shadow overflow-hidden">
        <div class="p-4 border-b">
          <h2 class="text-lg font-semibold">Recent Heartbeats</h2>
        </div>
        <table class="table w-full">
          <thead>
            <tr>
              <th>Timestamp</th>
              <th>Health Status</th>
              <th>Active Bundle</th>
              <th>Staged Bundle</th>
            </tr>
          </thead>
          <tbody>
            <%= for hb <- @heartbeats do %>
              <tr class="hover">
                <td class="text-sm">{format_datetime(hb.inserted_at)}</td>
                <td>
                  <.health_badge health={hb.health} />
                </td>
                <td class="font-mono text-sm">{hb.active_bundle_id || "-"}</td>
                <td class="font-mono text-sm">{hb.staged_bundle_id || "-"}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <%= if Enum.empty?(@heartbeats) do %>
          <div class="p-8 text-center text-gray-500">
            <p>No heartbeats recorded yet.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    {class, text} =
      case assigns.status do
        "online" -> {"badge-success", "Online"}
        "offline" -> {"badge-error", "Offline"}
        _ -> {"badge-ghost", "Unknown"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge #{@class}"}>{@text}</span>
    """
  end

  defp health_badge(assigns) do
    status = get_in(assigns.health, ["status"]) || "unknown"

    {class, text} =
      case status do
        "healthy" -> {"badge-success", "Healthy"}
        "degraded" -> {"badge-warning", "Degraded"}
        "unhealthy" -> {"badge-error", "Unhealthy"}
        _ -> {"badge-ghost", "Unknown"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_labels_for_edit(nil), do: ""

  defp format_labels_for_edit(labels) when labels == %{}, do: ""

  defp format_labels_for_edit(labels) do
    labels
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("\n")
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
