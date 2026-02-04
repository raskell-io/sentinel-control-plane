defmodule SentinelCpWeb.RolloutsLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Rollouts, Orgs, Projects, Nodes}

  @refresh_interval 5_000

  @impl true
  def mount(%{"project_slug" => slug, "id" => rollout_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         rollout when not is_nil(rollout) <- Rollouts.get_rollout_with_details(rollout_id),
         true <- rollout.project_id == project.id do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(SentinelCp.PubSub, "rollout:#{rollout.id}")
        :timer.send_interval(@refresh_interval, self(), :refresh)
      end

      progress = Rollouts.get_rollout_progress(rollout.id)
      node_names = load_node_names(rollout.node_bundle_statuses)

      {:ok,
       assign(socket,
         page_title: "Rollout — #{project.name}",
         org: org,
         project: project,
         rollout: rollout,
         progress: progress,
         node_names: node_names
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_event("pause", _, socket) do
    case Rollouts.pause_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout paused.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot pause rollout in current state.")}
    end
  end

  @impl true
  def handle_event("resume", _, socket) do
    case Rollouts.resume_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout resumed.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot resume rollout in current state.")}
    end
  end

  @impl true
  def handle_event("cancel", _, socket) do
    case Rollouts.cancel_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout cancelled.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot cancel rollout in current state.")}
    end
  end

  @impl true
  def handle_event("rollback", _, socket) do
    case Rollouts.rollback_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout rolled back. Affected nodes reverted.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot rollback rollout in current state.")}
    end
  end

  @impl true
  def handle_info({:rollout_updated, _rollout_id}, socket) do
    reload(socket)
  end

  @impl true
  def handle_info(:refresh, socket) do
    if socket.assigns.rollout.state in ~w(running paused) do
      reload(socket)
    else
      {:noreply, socket}
    end
  end

  defp reload(socket) do
    rollout = Rollouts.get_rollout_with_details(socket.assigns.rollout.id)
    progress = Rollouts.get_rollout_progress(rollout.id)
    node_names = load_node_names(rollout.node_bundle_statuses)

    {:noreply, assign(socket, rollout: rollout, progress: progress, node_names: node_names)}
  end

  defp load_node_names(node_bundle_statuses) do
    node_ids = Enum.map(node_bundle_statuses, & &1.node_id)

    if node_ids == [] do
      %{}
    else
      node_ids
      |> Enum.map(fn id ->
        case Nodes.get_node(id) do
          nil -> {id, "unknown"}
          node -> {id, node.name}
        end
      end)
      |> Map.new()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={"Rollout " <> String.slice(@rollout.id, 0, 8)}
        resource_type="rollout"
        back_path={project_rollouts_path(@org, @project)}
      >
        <:badge>
          <span class={[
            "badge badge-sm",
            @rollout.state == "completed" && "badge-success",
            @rollout.state == "running" && "badge-warning",
            @rollout.state == "failed" && "badge-error",
            @rollout.state == "cancelled" && "badge-error",
            @rollout.state == "paused" && "badge-info",
            @rollout.state == "pending" && "badge-ghost"
          ]}>
            {@rollout.state}
          </span>
        </:badge>
        <:action>
          <button :if={@rollout.state == "running"} class="btn btn-warning btn-sm" phx-click="pause">
            Pause
          </button>
          <button :if={@rollout.state == "paused"} class="btn btn-primary btn-sm" phx-click="resume">
            Resume
          </button>
          <button
            :if={@rollout.state in ~w(running paused)}
            class="btn btn-error btn-sm"
            phx-click="cancel"
          >
            Cancel
          </button>
          <button
            :if={@rollout.state in ~w(running paused)}
            class="btn btn-outline btn-error btn-sm"
            phx-click="rollback"
          >
            Rollback
          </button>
        </:action>
      </.detail_header>

      <.stat_strip>
        <:stat label="Total" value={to_string(@progress.total)} />
        <:stat label="Active" value={to_string(@progress.active)} color="success" />
        <:stat label="Pending" value={to_string(@progress.pending)} />
        <:stat label="Failed" value={to_string(@progress.failed)} color="error" />
      </.stat_strip>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@rollout.id}</span></:item>
            <:item label="Bundle"><span class="font-mono text-sm">{@rollout.bundle_id}</span></:item>
            <:item label="Strategy">{@rollout.strategy}</:item>
            <:item label="Batch Size">{@rollout.batch_size}</:item>
            <:item label="Target">{format_target(@rollout.target_selector)}</:item>
            <:item label="Started">
              {if @rollout.started_at,
                do: Calendar.strftime(@rollout.started_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Completed">
              {if @rollout.completed_at,
                do: Calendar.strftime(@rollout.completed_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
          </.definition_list>
        </.k8s_section>

        <div :if={@rollout.error}>
          <.k8s_section title="Error">
            <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap">{Jason.encode!(@rollout.error, pretty: true)}</pre>
          </.k8s_section>
        </div>
      </div>

      <.k8s_section title="Steps">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Step</th>
              <th class="text-xs uppercase">State</th>
              <th class="text-xs uppercase">Nodes</th>
              <th class="text-xs uppercase">Started</th>
              <th class="text-xs uppercase">Completed</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={step <- @rollout.steps}>
              <td>{step.step_index + 1}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  step.state == "completed" && "badge-success",
                  step.state == "running" && "badge-warning",
                  step.state == "verifying" && "badge-info",
                  step.state == "failed" && "badge-error",
                  step.state == "pending" && "badge-ghost"
                ]}>
                  {step.state}
                </span>
              </td>
              <td>{length(step.node_ids)}</td>
              <td class="text-sm">
                {if step.started_at, do: Calendar.strftime(step.started_at, "%H:%M:%S"), else: "—"}
              </td>
              <td class="text-sm">
                {if step.completed_at, do: Calendar.strftime(step.completed_at, "%H:%M:%S"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@rollout.steps == []} class="text-base-content/50 text-sm py-4">
          No steps created yet.
        </div>
      </.k8s_section>

      <.k8s_section title="Node Statuses">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Node</th>
              <th class="text-xs uppercase">State</th>
              <th class="text-xs uppercase">Staged</th>
              <th class="text-xs uppercase">Activated</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={nbs <- @rollout.node_bundle_statuses}>
              <td>
                <.link
                  navigate={node_show_path(@org, @project, nbs.node_id)}
                  class="flex items-center gap-2 text-primary hover:underline"
                >
                  <.resource_badge type="node" />
                  {Map.get(@node_names, nbs.node_id, nbs.node_id |> String.slice(0, 8))}
                </.link>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  nbs.state == "active" && "badge-success",
                  nbs.state in ~w(staging activating) && "badge-warning",
                  nbs.state == "failed" && "badge-error",
                  nbs.state == "pending" && "badge-ghost"
                ]}>
                  {nbs.state}
                </span>
              </td>
              <td class="text-sm">
                {if nbs.staged_at, do: Calendar.strftime(nbs.staged_at, "%H:%M:%S"), else: "—"}
              </td>
              <td class="text-sm">
                {if nbs.activated_at, do: Calendar.strftime(nbs.activated_at, "%H:%M:%S"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@rollout.node_bundle_statuses == []} class="text-base-content/50 text-sm py-4">
          No node statuses yet.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp project_rollouts_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts"

  defp project_rollouts_path(nil, project),
    do: ~p"/projects/#{project.slug}/rollouts"

  defp node_show_path(%{slug: org_slug}, project, node_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node_id}"

  defp node_show_path(nil, project, node_id),
    do: ~p"/projects/#{project.slug}/nodes/#{node_id}"

  defp format_target(%{"type" => "all"}), do: "All nodes"

  defp format_target(%{"type" => "labels", "labels" => labels}) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_target(%{"type" => "node_ids", "node_ids" => ids}) do
    "#{length(ids)} node(s)"
  end

  defp format_target(_), do: "—"
end
