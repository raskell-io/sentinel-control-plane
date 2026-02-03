defmodule SentinelCpWeb.BundlesLive.Diff do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Bundles, Bundles.Diff, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        bundles = Bundles.list_bundles(project.id)
        bundle_a_id = params["a"]
        bundle_b_id = params["b"]

        bundle_a = if bundle_a_id, do: Bundles.get_bundle(bundle_a_id)
        bundle_b = if bundle_b_id, do: Bundles.get_bundle(bundle_b_id)

        {diff, stats, manifest_diff} = compute_diff(bundle_a, bundle_b)

        {:ok,
         assign(socket,
           page_title: "Compare Bundles — #{project.name}",
           org: org,
           project: project,
           bundles: bundles,
           bundle_a: bundle_a,
           bundle_b: bundle_b,
           bundle_a_id: bundle_a_id || "",
           bundle_b_id: bundle_b_id || "",
           diff_lines: diff,
           diff_stats: stats,
           manifest_diff: manifest_diff
         )}
    end
  end

  @impl true
  def handle_event("compare", %{"a" => a_id, "b" => b_id}, socket) do
    project = socket.assigns.project
    org = socket.assigns.org

    path = diff_path(org, project, a_id, b_id)
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="text-sm breadcrumbs mb-4">
        <ul>
          <li><.link navigate={~p"/orgs"}>Organizations</.link></li>
          <li :if={@org}><.link navigate={~p"/orgs/#{@org.slug}/projects"}>{@org.name}</.link></li>
          <li><.link navigate={project_bundles_path(@org, @project)}>Bundles</.link></li>
          <li>Compare</li>
        </ul>
      </div>

      <h1 class="text-2xl font-bold mb-6">Compare Bundles</h1>

      <%!-- Bundle Selection --%>
      <form phx-submit="compare" class="flex items-end gap-4 mb-6">
        <div class="form-control">
          <label class="label"><span class="label-text">Bundle A (base)</span></label>
          <select name="a" class="select select-bordered select-sm">
            <option value="">Select bundle</option>
            <option :for={b <- @bundles} value={b.id} selected={b.id == @bundle_a_id}>
              {b.version} ({b.status})
            </option>
          </select>
        </div>
        <div class="form-control">
          <label class="label"><span class="label-text">Bundle B (new)</span></label>
          <select name="b" class="select select-bordered select-sm">
            <option value="">Select bundle</option>
            <option :for={b <- @bundles} value={b.id} selected={b.id == @bundle_b_id}>
              {b.version} ({b.status})
            </option>
          </select>
        </div>
        <button type="submit" class="btn btn-primary btn-sm">Compare</button>
      </form>

      <%!-- Diff Stats --%>
      <div :if={@diff_stats} class="flex gap-4 mb-4 text-sm">
        <span class="text-success">+{@diff_stats.additions} additions</span>
        <span class="text-error">-{@diff_stats.deletions} deletions</span>
        <span class="text-base-content/50">{@diff_stats.unchanged} unchanged</span>
      </div>

      <%!-- Config Diff --%>
      <div :if={@diff_lines} class="card bg-base-200 mb-6">
        <div class="card-body p-0">
          <h2 class="card-title text-lg p-4 pb-2">Configuration Diff</h2>
          <div class="overflow-x-auto">
            <table class="table table-xs font-mono">
              <tbody>
                <tr :for={line <- @diff_lines} class={diff_row_class(line.type)}>
                  <td class="text-right text-base-content/40 select-none w-12 px-2">
                    {line.number_a || ""}
                  </td>
                  <td class="text-right text-base-content/40 select-none w-12 px-2">
                    {line.number_b || ""}
                  </td>
                  <td class="select-none w-6 px-1">
                    {diff_marker(line.type)}
                  </td>
                  <td class="whitespace-pre">{line.line}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <%!-- Manifest Diff --%>
      <div :if={@manifest_diff} class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Manifest Diff</h2>
          <div :if={@manifest_diff.added != []} class="mb-2">
            <h3 class="text-sm font-medium text-success mb-1">Added files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.added}>{f}</li>
            </ul>
          </div>
          <div :if={@manifest_diff.removed != []} class="mb-2">
            <h3 class="text-sm font-medium text-error mb-1">Removed files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.removed}>{f}</li>
            </ul>
          </div>
          <div :if={@manifest_diff.modified != []} class="mb-2">
            <h3 class="text-sm font-medium text-warning mb-1">Modified files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.modified}>{f}</li>
            </ul>
          </div>
          <div
            :if={@manifest_diff.added == [] and @manifest_diff.removed == [] and @manifest_diff.modified == []}
            class="text-base-content/50 text-sm"
          >
            No manifest changes.
          </div>
        </div>
      </div>

      <div :if={is_nil(@bundle_a) or is_nil(@bundle_b)} class="text-center py-12 text-base-content/50">
        Select two bundles above to compare their configurations.
      </div>
    </div>
    """
  end

  defp compute_diff(nil, _), do: {nil, nil, nil}
  defp compute_diff(_, nil), do: {nil, nil, nil}

  defp compute_diff(bundle_a, bundle_b) do
    config_diff = Diff.config_diff(bundle_a, bundle_b)
    lines = Diff.annotate_diff(config_diff)
    stats = Diff.diff_stats(config_diff)
    manifest = Diff.manifest_diff(bundle_a, bundle_b)
    {lines, stats, manifest}
  end

  defp diff_row_class(:ins), do: "bg-success/10"
  defp diff_row_class(:del), do: "bg-error/10"
  defp diff_row_class(_), do: ""

  defp diff_marker(:ins), do: "+"
  defp diff_marker(:del), do: "-"
  defp diff_marker(_), do: " "

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_bundles_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles"

  defp project_bundles_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles"

  defp diff_path(%{slug: org_slug}, project, a_id, b_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"

  defp diff_path(nil, project, a_id, b_id),
    do: ~p"/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"
end
