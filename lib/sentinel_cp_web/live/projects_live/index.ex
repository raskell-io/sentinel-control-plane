defmodule SentinelCpWeb.ProjectsLive.Index do
  @moduledoc """
  LiveView for listing and managing projects.
  Supports both org-scoped (/orgs/:org_slug/projects) and legacy (/projects) routes.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Projects, Orgs}

  @impl true
  def mount(params, _session, socket) do
    case params do
      %{"org_slug" => org_slug} ->
        mount_org_scoped(org_slug, socket)

      _ ->
        mount_legacy(socket)
    end
  end

  defp mount_org_scoped(org_slug, socket) do
    case Orgs.get_org_by_slug(org_slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      org ->
        projects = Projects.list_projects(org_id: org.id)

        {:ok,
         socket
         |> assign(:org, org)
         |> assign(:projects, projects)
         |> assign(:page_title, "Projects — #{org.name}")}
    end
  end

  defp mount_legacy(socket) do
    # Legacy route: show all projects (for backward compat)
    # If user belongs to exactly one org, redirect there
    user = socket.assigns.current_user
    orgs = Orgs.list_user_orgs(user.id)

    case orgs do
      [{org, _role}] ->
        {:ok, push_navigate(socket, to: ~p"/orgs/#{org.slug}/projects")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="text-sm breadcrumbs mb-4">
        <ul>
          <li><.link navigate={~p"/orgs"}>Organizations</.link></li>
          <li><.link navigate={~p"/orgs/#{@org.slug}"}>{@org.name}</.link></li>
          <li>Projects</li>
        </ul>
      </div>

      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">Projects</h1>
          <p class="text-gray-500 mt-1">Manage your Sentinel deployments</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for project <- @projects do %>
          <.link
            navigate={~p"/orgs/#{@org.slug}/projects/#{project.slug}/nodes"}
            class="bg-base-100 rounded-lg shadow p-6 hover:shadow-lg transition-shadow"
          >
            <h2 class="text-lg font-semibold">{project.name}</h2>
            <p class="text-gray-500 text-sm mt-1">{project.description || "No description"}</p>
            <div class="mt-4 text-sm text-gray-400">
              <span class="font-mono">{project.slug}</span>
            </div>
          </.link>
        <% end %>
      </div>

      <%= if Enum.empty?(@projects) do %>
        <div class="bg-base-100 rounded-lg shadow p-8 text-center text-gray-500">
          <p>No projects yet.</p>
          <p class="text-sm mt-2">Create a project to get started.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
