defmodule SentinelCpWeb.DashboardLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Dashboard, Orgs, Projects}

  @refresh_interval 10_000

  @impl true
  def mount(%{"org_slug" => org_slug} = _params, _session, socket) do
    case Orgs.get_org_by_slug(org_slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      org ->
        if connected?(socket) do
          :timer.send_interval(@refresh_interval, self(), :refresh)
        end

        overview = Dashboard.get_org_overview(org.id)
        projects = Projects.list_projects(org_id: org.id)
        activity = Dashboard.get_recent_activity(org.id, 15)

        {:ok,
         assign(socket,
           page_title: "Dashboard — #{org.name}",
           org: org,
           overview: overview,
           projects: projects,
           activity: activity
         )}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    overview = Dashboard.get_org_overview(socket.assigns.org.id)
    activity = Dashboard.get_recent_activity(socket.assigns.org.id, 15)
    {:noreply, assign(socket, overview: overview, activity: activity)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-xl font-bold">Dashboard</h1>

      <.stat_strip>
        <:stat label="Projects" value={to_string(@overview.project_count)} />
        <:stat label="Nodes Online" value={to_string(@overview.node_stats.online)} color="success" />
        <:stat label="Nodes Offline" value={to_string(@overview.node_stats.offline)} color="error" />
        <:stat label="Active Rollouts" value={to_string(@overview.active_rollouts)} color="warning" />
        <:stat
          label="Success Rate"
          value={if @overview.deployment_success_rate, do: "#{@overview.deployment_success_rate}%", else: "—"}
          color="info"
        />
      </.stat_strip>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Fleet Health">
          <.node_health_chart stats={@overview.node_stats} />
        </.k8s_section>

        <.k8s_section title="Projects">
          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Name</th>
                <th class="text-xs uppercase">Nodes</th>
                <th class="text-xs uppercase"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={project <- @projects}>
                <td>
                  <span class="flex items-center gap-2">
                    <.resource_badge type="project" />
                    {project.name}
                  </span>
                </td>
                <td class="text-sm text-base-content/70">—</td>
                <td>
                  <.link
                    navigate={~p"/orgs/#{@org.slug}/projects/#{project.slug}/nodes"}
                    class="btn btn-ghost btn-xs"
                  >
                    View
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
          <div :if={@projects == []} class="text-base-content/50 text-sm">
            No projects yet.
          </div>
        </.k8s_section>

        <.k8s_section title="Recent Activity" class="lg:col-span-2">
          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Action</th>
                <th class="text-xs uppercase">Resource</th>
                <th class="text-xs uppercase">Actor</th>
                <th class="text-xs uppercase">When</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @activity}>
                <td class="text-sm">{entry.action}</td>
                <td class="text-sm font-mono">
                  {entry.resource_type}/{entry.resource_id |> String.slice(0, 8)}
                </td>
                <td class="text-sm">{entry.actor_type}</td>
                <td class="text-sm">{format_relative(entry.inserted_at)}</td>
              </tr>
            </tbody>
          </table>
          <div :if={@activity == []} class="text-base-content/50 text-sm">
            No recent activity.
          </div>
        </.k8s_section>
      </div>
    </div>
    """
  end

  defp node_health_chart(assigns) do
    total = assigns.stats.total
    online = assigns.stats.online
    offline = assigns.stats.offline
    unknown = total - online - offline

    assigns =
      assign(assigns,
        total: total,
        online: online,
        offline: offline,
        unknown: unknown,
        online_pct: if(total > 0, do: Float.round(online / total * 100, 1), else: 0),
        offline_pct: if(total > 0, do: Float.round(offline / total * 100, 1), else: 0)
      )

    ~H"""
    <div :if={@total == 0} class="text-base-content/50 text-sm py-8 text-center">
      No nodes registered.
    </div>
    <div :if={@total > 0} class="space-y-3">
      <div class="flex items-center gap-3">
        <span class="w-20 text-sm">Online</span>
        <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
          <div class="bg-success h-full rounded-full transition-all" style={"width: #{@online_pct}%"}></div>
        </div>
        <span class="text-sm font-mono w-16 text-right">{@online}/{@total}</span>
      </div>
      <div class="flex items-center gap-3">
        <span class="w-20 text-sm">Offline</span>
        <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
          <div class="bg-error h-full rounded-full transition-all" style={"width: #{@offline_pct}%"}></div>
        </div>
        <span class="text-sm font-mono w-16 text-right">{@offline}/{@total}</span>
      </div>
      <div :if={@unknown > 0} class="flex items-center gap-3">
        <span class="w-20 text-sm">Unknown</span>
        <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
          <div class="bg-base-content/30 h-full rounded-full transition-all" style={"width: #{Float.round(@unknown / @total * 100, 1)}%"}></div>
        </div>
        <span class="text-sm font-mono w-16 text-right">{@unknown}/{@total}</span>
      </div>
    </div>
    """
  end

  defp format_relative(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
