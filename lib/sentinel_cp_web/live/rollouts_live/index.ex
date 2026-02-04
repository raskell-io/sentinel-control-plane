defmodule SentinelCpWeb.RolloutsLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Rollouts, Bundles, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "rollouts:#{project.id}")
        end

        rollouts = Rollouts.list_rollouts(project.id)
        compiled_bundles = Bundles.list_bundles(project.id, status: "compiled")

        {:ok,
         assign(socket,
           page_title: "Rollouts — #{project.name}",
           org: org,
           project: project,
           rollouts: rollouts,
           compiled_bundles: compiled_bundles,
           show_form: false
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  @impl true
  def handle_event("create_rollout", params, socket) do
    project = socket.assigns.project

    target_selector =
      case params["target_type"] do
        "all" ->
          %{"type" => "all"}

        "labels" ->
          %{"type" => "labels", "labels" => parse_labels(params["labels"] || "")}

        "node_ids" ->
          %{"type" => "node_ids", "node_ids" => parse_node_ids(params["node_ids"] || "")}

        _ ->
          %{"type" => "all"}
      end

    attrs = %{
      project_id: project.id,
      bundle_id: params["bundle_id"],
      target_selector: target_selector,
      strategy: params["strategy"] || "rolling",
      batch_size: parse_int(params["batch_size"], 1)
    }

    case Rollouts.create_rollout(attrs) do
      {:ok, rollout} ->
        case Rollouts.plan_rollout(rollout) do
          {:ok, _} ->
            rollouts = Rollouts.list_rollouts(project.id)

            {:noreply,
             socket
             |> assign(rollouts: rollouts, show_form: false)
             |> put_flash(:info, "Rollout created and started.")}

          {:error, :no_target_nodes} ->
            {:noreply, put_flash(socket, :error, "No target nodes matched the selector.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to plan rollout: #{inspect(reason)}")}
        end

      {:error, :bundle_not_compiled} ->
        {:noreply, put_flash(socket, :error, "Bundle must be compiled before rollout.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed to create rollout: #{errors}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create rollout: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:rollout_updated, _rollout_id}, socket) do
    rollouts = Rollouts.list_rollouts(socket.assigns.project.id)
    {:noreply, assign(socket, rollouts: rollouts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Rollouts</h1>
        </:filters>
        <:actions>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Rollout
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title="Create Rollout">
          <form phx-submit="create_rollout" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Bundle</span></label>
              <select name="bundle_id" required class="select select-bordered select-sm w-full max-w-xs">
                <option value="">Select a compiled bundle</option>
                <option :for={bundle <- @compiled_bundles} value={bundle.id}>
                  {bundle.version}
                </option>
              </select>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Target</span></label>
              <select name="target_type" class="select select-bordered select-sm w-full max-w-xs">
                <option value="all">All nodes</option>
                <option value="labels">By labels</option>
                <option value="node_ids">Specific node IDs</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Labels (key=value, comma-separated)</span></label>
              <input
                type="text"
                name="labels"
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="env=production,region=us-east"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Node IDs (comma-separated)</span></label>
              <input
                type="text"
                name="node_ids"
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="node-id-1,node-id-2"
              />
            </div>
            <div class="flex gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Strategy</span></label>
                <select name="strategy" class="select select-bordered select-sm">
                  <option value="rolling">Rolling</option>
                  <option value="all_at_once">All at once</option>
                </select>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Batch Size</span></label>
                <input
                  type="number"
                  name="batch_size"
                  value="1"
                  min="1"
                  class="input input-bordered input-sm w-24"
                />
              </div>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create & Start</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">Cancel</button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">ID</th>
              <th class="text-xs uppercase">State</th>
              <th class="text-xs uppercase">Bundle</th>
              <th class="text-xs uppercase">Strategy</th>
              <th class="text-xs uppercase">Target</th>
              <th class="text-xs uppercase">Started</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={rollout <- @rollouts}>
              <td>
                <.link
                  navigate={rollout_show_path(@org, @project, rollout)}
                  class="flex items-center gap-2 text-primary hover:underline font-mono text-sm"
                >
                  <.resource_badge type="rollout" />
                  {String.slice(rollout.id, 0, 8)}
                </.link>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  rollout.state == "completed" && "badge-success",
                  rollout.state == "running" && "badge-warning",
                  rollout.state == "failed" && "badge-error",
                  rollout.state == "cancelled" && "badge-error",
                  rollout.state == "paused" && "badge-info",
                  rollout.state == "pending" && "badge-ghost"
                ]}>
                  {rollout.state}
                </span>
              </td>
              <td class="font-mono text-sm">{rollout.bundle_id |> String.slice(0, 8)}</td>
              <td class="text-sm">{rollout.strategy}</td>
              <td class="text-sm">{format_target(rollout.target_selector)}</td>
              <td class="text-sm">
                {if rollout.started_at,
                  do: Calendar.strftime(rollout.started_at, "%Y-%m-%d %H:%M"),
                  else: "—"}
              </td>
              <td>
                <.link
                  navigate={rollout_show_path(@org, @project, rollout)}
                  class="btn btn-ghost btn-xs"
                >
                  Details
                </.link>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@rollouts == []} class="text-center py-12 text-base-content/50">
          No rollouts yet. Create one to deploy a bundle.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp rollout_show_path(%{slug: org_slug}, project, rollout),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts/#{rollout.id}"

  defp rollout_show_path(nil, project, rollout),
    do: ~p"/projects/#{project.slug}/rollouts/#{rollout.id}"

  defp format_target(%{"type" => "all"}), do: "All nodes"

  defp format_target(%{"type" => "labels", "labels" => labels}) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_target(%{"type" => "node_ids", "node_ids" => ids}) do
    "#{length(ids)} node(s)"
  end

  defp format_target(_), do: "—"

  defp parse_labels(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp parse_node_ids(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end
end
