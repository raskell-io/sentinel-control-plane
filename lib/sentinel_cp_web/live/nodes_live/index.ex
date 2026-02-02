defmodule SentinelCpWeb.NodesLive.Index do
  @moduledoc """
  LiveView for listing and managing nodes.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Nodes, Projects}

  @impl true
  def mount(%{"project_slug" => project_slug}, _session, socket) do
    case Projects.get_project_by_slug(project_slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Project not found") |> redirect(to: ~p"/")}

      project ->
        if connected?(socket) do
          # Subscribe to node updates
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "nodes:#{project.id}")
          # Refresh every 10 seconds
          :timer.send_interval(10_000, self(), :refresh)
        end

        nodes = Nodes.list_nodes(project.id)
        stats = Nodes.get_node_stats(project.id)

        {:ok,
         socket
         |> assign(:project, project)
         |> assign(:nodes, nodes)
         |> assign(:stats, stats)
         |> assign(:status_filter, nil)
         |> assign(:page_title, "Nodes - #{project.name}")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    status_filter = params["status"]
    {:noreply, apply_filter(socket, status_filter)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: status

    {:noreply,
     push_patch(socket,
       to: ~p"/projects/#{socket.assigns.project.slug}/nodes?#{[status: status]}"
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => node_id}, socket) do
    node = Nodes.get_node!(node_id)

    case Nodes.delete_node(node) do
      {:ok, _} ->
        nodes = filter_nodes(socket.assigns.project.id, socket.assigns.status_filter)
        {:noreply, socket |> assign(:nodes, nodes) |> put_flash(:info, "Node deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete node")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    nodes = filter_nodes(socket.assigns.project.id, socket.assigns.status_filter)
    stats = Nodes.get_node_stats(socket.assigns.project.id)
    {:noreply, assign(socket, nodes: nodes, stats: stats)}
  end

  @impl true
  def handle_info({:node_updated, _node}, socket) do
    nodes = filter_nodes(socket.assigns.project.id, socket.assigns.status_filter)
    stats = Nodes.get_node_stats(socket.assigns.project.id)
    {:noreply, assign(socket, nodes: nodes, stats: stats)}
  end

  defp apply_filter(socket, status_filter) do
    nodes = filter_nodes(socket.assigns.project.id, status_filter)
    assign(socket, nodes: nodes, status_filter: status_filter)
  end

  defp filter_nodes(project_id, nil), do: Nodes.list_nodes(project_id)
  defp filter_nodes(project_id, status), do: Nodes.list_nodes(project_id, status: status)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">{@project.name} / Nodes</h1>
          <p class="text-gray-500 mt-1">Manage Sentinel proxy instances</p>
        </div>
      </div>
      
    <!-- Stats Cards -->
      <div class="grid grid-cols-4 gap-4 mb-6">
        <.stat_card label="Total" value={Enum.count(@nodes)} color="blue" />
        <.stat_card label="Online" value={Map.get(@stats, "online", 0)} color="green" />
        <.stat_card label="Offline" value={Map.get(@stats, "offline", 0)} color="red" />
        <.stat_card label="Unknown" value={Map.get(@stats, "unknown", 0)} color="gray" />
      </div>
      
    <!-- Filters -->
      <div class="flex gap-4 mb-4">
        <form phx-change="filter" class="flex gap-2">
          <select name="status" class="select select-bordered select-sm">
            <option value="">All statuses</option>
            <option value="online" selected={@status_filter == "online"}>Online</option>
            <option value="offline" selected={@status_filter == "offline"}>Offline</option>
            <option value="unknown" selected={@status_filter == "unknown"}>Unknown</option>
          </select>
        </form>
      </div>
      
    <!-- Nodes Table -->
      <div class="bg-base-100 rounded-lg shadow overflow-hidden">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Name</th>
              <th>Status</th>
              <th>Version</th>
              <th>IP</th>
              <th>Last Seen</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for node <- @nodes do %>
              <tr class="hover">
                <td>
                  <.link
                    navigate={~p"/projects/#{@project.slug}/nodes/#{node.id}"}
                    class="font-medium text-primary hover:underline"
                  >
                    {node.name}
                  </.link>
                </td>
                <td>
                  <.status_badge status={node.status} />
                </td>
                <td class="font-mono text-sm">{node.version || "-"}</td>
                <td class="font-mono text-sm">{node.ip || "-"}</td>
                <td class="text-sm text-gray-500">
                  {if node.last_seen_at, do: format_relative_time(node.last_seen_at), else: "Never"}
                </td>
                <td>
                  <button
                    phx-click="delete"
                    phx-value-id={node.id}
                    data-confirm="Are you sure you want to delete this node?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%= if Enum.empty?(@nodes) do %>
          <div class="p-8 text-center text-gray-500">
            <p>No nodes found.</p>
            <p class="text-sm mt-2">
              Nodes will appear here once they register with the control plane.
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    color_class =
      case assigns.color do
        "green" -> "text-success"
        "red" -> "text-error"
        "blue" -> "text-info"
        _ -> "text-gray-500"
      end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <div class="bg-base-100 rounded-lg shadow p-4">
      <div class="text-sm text-gray-500">{@label}</div>
      <div class={"text-2xl font-bold #{@color_class}"}>{@value}</div>
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
