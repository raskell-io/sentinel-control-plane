defmodule SentinelCpWeb.BundlesLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Bundles, Orgs, Projects, Nodes}

  @impl true
  def mount(%{"project_slug" => slug, "id" => bundle_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         bundle when not is_nil(bundle) <- Bundles.get_bundle(bundle_id),
         true <- bundle.project_id == project.id do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(SentinelCp.PubSub, "bundles:#{project.id}")
      end

      assigned_nodes = get_assigned_nodes(bundle, project.id)

      {:ok,
       assign(socket,
         page_title: "Bundle #{bundle.version} — #{project.name}",
         org: org,
         project: project,
         bundle: bundle,
         assigned_nodes: assigned_nodes
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_info({:bundle_compiled, bundle_id}, socket) do
    if bundle_id == socket.assigns.bundle.id do
      bundle = Bundles.get_bundle!(bundle_id)
      {:noreply, assign(socket, bundle: bundle)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:bundle_failed, bundle_id}, socket) do
    if bundle_id == socket.assigns.bundle.id do
      bundle = Bundles.get_bundle!(bundle_id)
      {:noreply, assign(socket, bundle: bundle)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke", _, socket) do
    bundle = socket.assigns.bundle

    case Bundles.revoke_bundle(bundle) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "revoke", "bundle", bundle.id,
          project_id: socket.assigns.project.id
        )

        {:noreply, socket |> assign(bundle: updated) |> put_flash(:info, "Bundle revoked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revoke bundle.")}
    end
  end

  def handle_event("delete", _, socket) do
    bundle = socket.assigns.bundle
    project = socket.assigns.project
    org = socket.assigns.org

    case Bundles.delete_bundle(bundle) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "bundle", bundle.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Bundle deleted.")
         |> push_navigate(to: project_bundles_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete bundle.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="text-sm breadcrumbs mb-4">
        <ul>
          <li><.link navigate={~p"/orgs"}>Organizations</.link></li>
          <li :if={@org}><.link navigate={~p"/orgs/#{@org.slug}/projects"}>{@org.name}</.link></li>
          <li><.link navigate={project_nodes_path(@org, @project)}>{@project.name}</.link></li>
          <li><.link navigate={project_bundles_path(@org, @project)}>Bundles</.link></li>
          <li>{@bundle.version}</li>
        </ul>
      </div>

      <div class="flex items-center gap-4 mb-6">
        <h1 class="text-2xl font-bold font-mono">{@bundle.version}</h1>
        <span class={[
          "badge",
          @bundle.status == "compiled" && "badge-success",
          @bundle.status == "compiling" && "badge-warning",
          @bundle.status == "failed" && "badge-error",
          @bundle.status == "pending" && "badge-ghost"
        ]}>
          {@bundle.status}
        </span>
        <a
          :if={@bundle.status == "compiled"}
          href={"/api/v1/projects/#{@project.slug}/bundles/#{@bundle.id}/sbom"}
          class="btn btn-outline btn-sm"
          target="_blank"
        >
          Download SBOM
        </a>
        <button
          :if={@bundle.status == "compiled"}
          phx-click="revoke"
          data-confirm="Are you sure you want to revoke this bundle?"
          class="btn btn-warning btn-sm"
        >
          Revoke
        </button>
        <button
          :if={@bundle.status in ["pending", "failed"]}
          phx-click="delete"
          data-confirm="Are you sure you want to delete this bundle?"
          class="btn btn-error btn-sm"
        >
          Delete
        </button>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- Metadata --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-lg">Metadata</h2>
            <table class="table table-sm">
              <tbody>
                <tr>
                  <td class="font-medium">ID</td>
                  <td class="font-mono text-sm">{@bundle.id}</td>
                </tr>
                <tr>
                  <td class="font-medium">Version</td>
                  <td class="font-mono">{@bundle.version}</td>
                </tr>
                <tr>
                  <td class="font-medium">Status</td>
                  <td>{@bundle.status}</td>
                </tr>
                <tr>
                  <td class="font-medium">Checksum</td>
                  <td class="font-mono text-sm">{@bundle.checksum || "—"}</td>
                </tr>
                <tr>
                  <td class="font-medium">Size</td>
                  <td class="font-mono">
                    {if @bundle.size_bytes, do: format_bytes(@bundle.size_bytes), else: "—"}
                  </td>
                </tr>
                <tr>
                  <td class="font-medium">Risk Level</td>
                  <td>{@bundle.risk_level}</td>
                </tr>
                <tr>
                  <td class="font-medium">Created</td>
                  <td>{Calendar.strftime(@bundle.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Assigned Nodes --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-lg">Assigned Nodes</h2>
            <div :if={@assigned_nodes == []} class="text-base-content/50 text-sm">
              No nodes assigned to this bundle.
            </div>
            <table :if={@assigned_nodes != []} class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={node <- @assigned_nodes}>
                  <td>
                    <.link
                      navigate={node_show_path(@org, @project, node)}
                      class="link link-primary"
                    >
                      {node.name}
                    </.link>
                  </td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      node.status == "online" && "badge-success",
                      node.status == "offline" && "badge-error",
                      "badge-ghost"
                    ]}>
                      {node.status}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Compiler Output --%>
        <div :if={@bundle.compiler_output} class="card bg-base-200 lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title text-lg">Compiler Output</h2>
            <pre class="bg-base-300 p-4 rounded-lg text-sm font-mono whitespace-pre-wrap overflow-x-auto">{@bundle.compiler_output}</pre>
          </div>
        </div>

        <%!-- Config Source --%>
        <div class="card bg-base-200 lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title text-lg">Configuration Source</h2>
            <pre class="bg-base-300 p-4 rounded-lg text-sm font-mono whitespace-pre-wrap overflow-x-auto">{@bundle.config_source}</pre>
          </div>
        </div>

        <%!-- Manifest --%>
        <div :if={@bundle.manifest != %{}} class="card bg-base-200 lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title text-lg">Manifest</h2>
            <pre class="bg-base-300 p-4 rounded-lg text-sm font-mono whitespace-pre-wrap overflow-x-auto">{Jason.encode!(@bundle.manifest, pretty: true)}</pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp project_nodes_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes"

  defp project_nodes_path(nil, project),
    do: ~p"/projects/#{project.slug}/nodes"

  defp project_bundles_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles"

  defp project_bundles_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles"

  defp node_show_path(%{slug: org_slug}, project, node),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node.id}"

  defp node_show_path(nil, project, node),
    do: ~p"/projects/#{project.slug}/nodes/#{node.id}"

  defp get_assigned_nodes(bundle, project_id) do
    Nodes.list_nodes(project_id)
    |> Enum.filter(fn node ->
      node.staged_bundle_id == bundle.id || node.active_bundle_id == bundle.id
    end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
