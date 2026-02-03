defmodule SentinelCpWeb.BundlesLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Bundles, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "bundles:#{project.id}")
        end

        bundles = Bundles.list_bundles(project.id)

        {:ok,
         assign(socket,
           page_title: "Bundles — #{project.name}",
           org: org,
           project: project,
           bundles: bundles,
           show_upload: false
         )}
    end
  end

  @impl true
  def handle_event("toggle_upload", _, socket) do
    {:noreply, assign(socket, show_upload: !socket.assigns.show_upload)}
  end

  @impl true
  def handle_event(
        "create_bundle",
        %{"version" => version, "config_source" => config_source},
        socket
      ) do
    project = socket.assigns.project

    case Bundles.create_bundle(%{
           project_id: project.id,
           version: version,
           config_source: config_source
         }) do
      {:ok, _bundle} ->
        bundles = Bundles.list_bundles(project.id)

        {:noreply,
         socket
         |> assign(bundles: bundles, show_upload: false)
         |> put_flash(:info, "Bundle created, compilation started.")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed to create bundle: #{errors}")}
    end
  end

  @impl true
  def handle_info({:bundle_compiled, _bundle_id}, socket) do
    bundles = Bundles.list_bundles(socket.assigns.project.id)
    {:noreply, assign(socket, bundles: bundles)}
  end

  @impl true
  def handle_info({:bundle_failed, _bundle_id}, socket) do
    bundles = Bundles.list_bundles(socket.assigns.project.id)
    {:noreply, assign(socket, bundles: bundles)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <div>
          <div class="text-sm breadcrumbs mb-2">
            <ul>
              <li><.link navigate={~p"/orgs"}>Organizations</.link></li>
              <li :if={@org}><.link navigate={~p"/orgs/#{@org.slug}/projects"}>{@org.name}</.link></li>
              <li><.link navigate={project_nodes_path(@org, @project)}>{@project.name}</.link></li>
              <li>Bundles</li>
            </ul>
          </div>
          <h1 class="text-2xl font-bold">Bundles</h1>
        </div>
        <button class="btn btn-primary btn-sm" phx-click="toggle_upload">
          New Bundle
        </button>
      </div>

      <div :if={@show_upload} class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">Create Bundle</h2>
          <form phx-submit="create_bundle" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Version</span></label>
              <input
                type="text"
                name="version"
                required
                class="input input-bordered w-full max-w-xs"
                placeholder="e.g. 1.0.0"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">KDL Configuration</span></label>
              <textarea
                name="config_source"
                required
                rows="12"
                class="textarea textarea-bordered font-mono text-sm w-full"
                placeholder="// Paste your sentinel.kdl config here"
              ></textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create & Compile</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_upload">
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>Version</th>
              <th>Status</th>
              <th>Size</th>
              <th>Checksum</th>
              <th>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={bundle <- @bundles} class="hover">
              <td class="font-mono">{bundle.version}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  bundle.status == "compiled" && "badge-success",
                  bundle.status == "compiling" && "badge-warning",
                  bundle.status == "failed" && "badge-error",
                  bundle.status == "pending" && "badge-ghost"
                ]}>
                  {bundle.status}
                </span>
              </td>
              <td class="font-mono text-sm">
                {if bundle.size_bytes, do: format_bytes(bundle.size_bytes), else: "—"}
              </td>
              <td class="font-mono text-xs">
                {if bundle.checksum, do: String.slice(bundle.checksum, 0, 12) <> "…", else: "—"}
              </td>
              <td class="text-sm">{Calendar.strftime(bundle.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td>
                <.link
                  navigate={{bundle_show_path(@org, @project, bundle)}}
                  class="btn btn-ghost btn-xs"
                >
                  Details
                </.link>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@bundles == []} class="text-center py-12 text-base-content/50">
          No bundles yet. Create one to get started.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_nodes_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes"

  defp project_nodes_path(nil, project),
    do: ~p"/projects/#{project.slug}/nodes"

  defp bundle_show_path(%{slug: org_slug}, project, bundle),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_show_path(nil, project, bundle),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle.id}"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
