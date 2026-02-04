defmodule SentinelCpWeb.NodesLive.Index do
  @moduledoc """
  LiveView for listing and managing nodes.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Nodes, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => project_slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(project_slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Project not found") |> redirect(to: ~p"/")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "nodes:#{project.id}")
          :timer.send_interval(10_000, self(), :refresh)
        end

        nodes = Nodes.list_nodes(project.id)
        stats = Nodes.get_node_stats(project.id)

        {:ok,
         socket
         |> assign(:org, org)
         |> assign(:project, project)
         |> assign(:nodes, nodes)
         |> assign(:stats, stats)
         |> assign(:status_filter, nil)
         |> assign(:show_form, false)
         |> assign(:created_node_key, nil)
         |> assign(:page_title, "Nodes - #{project.name}")}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_params(params, _url, socket) do
    status_filter = params["status"]
    {:noreply, apply_filter(socket, status_filter)}
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form, created_node_key: nil)}
  end

  def handle_event("dismiss_key", _, socket) do
    {:noreply, assign(socket, created_node_key: nil)}
  end

  def handle_event("create_node", params, socket) do
    project = socket.assigns.project

    labels =
      (params["labels"] || "")
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
          _ -> acc
        end
      end)

    attrs = %{
      project_id: project.id,
      name: params["name"],
      hostname: if(params["hostname"] != "", do: params["hostname"]),
      ip: if(params["ip"] != "", do: params["ip"]),
      version: if(params["version"] != "", do: params["version"]),
      labels: labels
    }

    case Nodes.register_node(attrs) do
      {:ok, node} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "node", node.id,
          project_id: project.id
        )

        nodes = filter_nodes(project.id, socket.assigns.status_filter)
        stats = Nodes.get_node_stats(project.id)

        {:noreply,
         socket
         |> assign(nodes: nodes, stats: stats, show_form: false, created_node_key: node.node_key)
         |> put_flash(:info, "Node registered.")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)
          |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
          |> Enum.join("; ")

        {:noreply, put_flash(socket, :error, "Could not register node: #{errors}")}
    end
  end

  def handle_event("filter", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: status

    {:noreply,
     push_patch(socket,
       to: node_path(socket.assigns.org, socket.assigns.project, status: status)
     )}
  end

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
        <button class="btn btn-primary btn-sm" phx-click="toggle_form">
          Register Node
        </button>
      </div>

      <%!-- Node key banner (shown once after creation) --%>
      <div :if={@created_node_key} class="alert alert-warning mb-6">
        <div class="flex-1">
          <p class="font-semibold">Save this node key — it will not be shown again.</p>
          <pre class="mt-2 bg-base-300 p-3 rounded font-mono text-sm select-all">{@created_node_key}</pre>
        </div>
        <button class="btn btn-ghost btn-sm" phx-click="dismiss_key">Dismiss</button>
      </div>

      <%!-- Create Node Form --%>
      <div :if={@show_form} class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">Register Node</h2>
          <form phx-submit="create_node" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                class="input input-bordered w-full max-w-xs"
                placeholder="e.g. edge-node-01"
              />
              <label class="label">
                <span class="label-text-alt">Alphanumeric, underscore, dot, or hyphen</span>
              </label>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Hostname</span></label>
                <input
                  type="text"
                  name="hostname"
                  class="input input-bordered w-full"
                  placeholder="optional"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">IP Address</span></label>
                <input
                  type="text"
                  name="ip"
                  class="input input-bordered w-full"
                  placeholder="optional"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Version</span></label>
                <input
                  type="text"
                  name="version"
                  class="input input-bordered w-full"
                  placeholder="optional"
                />
              </div>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Labels (one key=value per line)</span></label>
              <textarea
                name="labels"
                rows="3"
                class="textarea textarea-bordered font-mono text-sm w-full max-w-md"
                placeholder={"env=production\nregion=us-east-1"}
              ></textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Register</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
                Cancel
              </button>
            </div>
          </form>
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
                    navigate={node_show_path(@org, @project, node)}
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
              Register a node above or let nodes self-register via the API.
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

  defp node_path(%{slug: org_slug}, project, query) do
    ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes?#{query}"
  end

  defp node_path(nil, project, query) do
    ~p"/projects/#{project.slug}/nodes?#{query}"
  end

  defp node_show_path(%{slug: org_slug}, project, node) do
    ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node.id}"
  end

  defp node_show_path(nil, project, node) do
    ~p"/projects/#{project.slug}/nodes/#{node.id}"
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
