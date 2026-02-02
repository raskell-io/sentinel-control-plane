defmodule SentinelCpWeb.AuditLive.Index do
  @moduledoc """
  LiveView for viewing audit logs. Admin-only.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.Audit

  on_mount {SentinelCpWeb.LiveHelpers, :require_admin}

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Audit.subscribe()

    socket =
      socket
      |> assign(page_title: "Audit Log")
      |> assign(page: 0)
      |> assign(filters: %{})
      |> load_logs()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      action: params["action"],
      resource_type: params["resource_type"],
      actor_type: params["actor_type"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()

    page = parse_page(params["page"])

    socket =
      socket
      |> assign(page: page)
      |> assign(filters: filters)
      |> load_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{
        "action" => params["action"],
        "resource_type" => params["resource_type"],
        "actor_type" => params["actor_type"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/audit?#{query_params}")}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    params = Map.put(socket.assigns.filters, "page", page)
    {:noreply, push_patch(socket, to: ~p"/audit?#{params}")}
  end

  @impl true
  def handle_info({:audit_log_created, log_entry}, socket) do
    # Prepend new entry if it matches current filters
    if matches_filters?(log_entry, socket.assigns.filters) and socket.assigns.page == 0 do
      logs = [log_entry | Enum.take(socket.assigns.logs, @per_page - 1)]
      {:noreply, assign(socket, logs: logs, total: socket.assigns.total + 1)}
    else
      {:noreply, assign(socket, total: socket.assigns.total + 1)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-6">
      <h1 class="text-2xl font-bold mb-6">Audit Log</h1>

      <form phx-change="filter" class="mb-6 flex gap-4">
        <select name="action" class="border rounded px-3 py-2 text-sm">
          <option value="">All actions</option>
          <%= for action <- @available_actions do %>
            <option value={action} selected={@filters[:action] == action}><%= action %></option>
          <% end %>
        </select>

        <select name="resource_type" class="border rounded px-3 py-2 text-sm">
          <option value="">All resources</option>
          <%= for type <- @available_resource_types do %>
            <option value={type} selected={@filters[:resource_type] == type}><%= type %></option>
          <% end %>
        </select>

        <select name="actor_type" class="border rounded px-3 py-2 text-sm">
          <option value="">All actors</option>
          <option value="user" selected={@filters[:actor_type] == "user"}>User</option>
          <option value="api_key" selected={@filters[:actor_type] == "api_key"}>API Key</option>
          <option value="system" selected={@filters[:actor_type] == "system"}>System</option>
          <option value="node" selected={@filters[:actor_type] == "node"}>Node</option>
        </select>
      </form>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Action</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actor</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Resource</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Resource ID</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Project</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <%= for log <- @logs do %>
              <tr class="hover:bg-gray-50">
                <td class="px-4 py-3 text-sm text-gray-500 whitespace-nowrap">
                  <%= Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M:%S") %>
                </td>
                <td class="px-4 py-3 text-sm font-medium">
                  <span class={"px-2 py-1 rounded text-xs #{action_color(log.action)}"}>
                    <%= log.action %>
                  </span>
                </td>
                <td class="px-4 py-3 text-sm text-gray-500">
                  <span class="text-xs text-gray-400"><%= log.actor_type %></span>
                  <br />
                  <span class="text-xs font-mono"><%= short_id(log.actor_id) %></span>
                </td>
                <td class="px-4 py-3 text-sm text-gray-500"><%= log.resource_type %></td>
                <td class="px-4 py-3 text-sm text-gray-500 font-mono"><%= short_id(log.resource_id) %></td>
                <td class="px-4 py-3 text-sm text-gray-500 font-mono"><%= short_id(log.project_id) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <!-- Pagination -->
      <div class="mt-4 flex items-center justify-between">
        <p class="text-sm text-gray-500">
          Showing <%= @page * @per_page + 1 %>-<%= min((@page + 1) * @per_page, @total) %> of <%= @total %>
        </p>
        <div class="flex gap-2">
          <%= if @page > 0 do %>
            <button phx-click="page" phx-value-page={@page - 1} class="px-3 py-1 border rounded text-sm hover:bg-gray-50">
              Previous
            </button>
          <% end %>
          <%= if (@page + 1) * @per_page < @total do %>
            <button phx-click="page" phx-value-page={@page + 1} class="px-3 py-1 border rounded text-sm hover:bg-gray-50">
              Next
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_logs(socket) do
    filters = socket.assigns.filters
    page = socket.assigns.page

    opts =
      [limit: @per_page, offset: page * @per_page]
      |> maybe_add_filter(:action, filters[:action])
      |> maybe_add_filter(:resource_type, filters[:resource_type])
      |> maybe_add_filter(:actor_type, filters[:actor_type])

    {logs, total} = Audit.list_all_audit_logs(opts)

    socket
    |> assign(logs: logs, total: total, per_page: @per_page)
    |> assign(available_actions: available_actions())
    |> assign(available_resource_types: available_resource_types())
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: [{key, value} | opts]

  defp matches_filters?(log_entry, filters) do
    Enum.all?(filters, fn
      {:action, action} -> log_entry.action == action
      {:resource_type, type} -> log_entry.resource_type == type
      {:actor_type, type} -> log_entry.actor_type == type
      _ -> true
    end)
  end

  defp parse_page(nil), do: 0
  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp short_id(nil), do: "-"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8) <> "..."

  defp action_color(action) do
    cond do
      String.contains?(action, "created") -> "bg-green-100 text-green-800"
      String.contains?(action, "deleted") -> "bg-red-100 text-red-800"
      String.contains?(action, "failed") -> "bg-red-100 text-red-800"
      String.contains?(action, "login") -> "bg-blue-100 text-blue-800"
      String.contains?(action, "logout") -> "bg-gray-100 text-gray-800"
      String.contains?(action, "revoked") -> "bg-yellow-100 text-yellow-800"
      true -> "bg-gray-100 text-gray-800"
    end
  end

  defp available_actions do
    ~w(
      session.login session.logout
      bundle.created bundle.compiled bundle.compilation_failed
      bundle.downloaded bundle.assigned
      node.deleted
      rollout.created rollout.paused rollout.resumed
      rollout.cancelled rollout.rolled_back
      api_key.created api_key.revoked api_key.deleted
    )
  end

  defp available_resource_types do
    ~w(user bundle node rollout api_key)
  end
end
