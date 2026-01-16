defmodule SentinelCpWeb.ProjectsLive.Index do
  @moduledoc """
  LiveView for listing and managing projects.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.Projects

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list_projects()

    {:ok,
     socket
     |> assign(:projects, projects)
     |> assign(:page_title, "Projects")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">Projects</h1>
          <p class="text-gray-500 mt-1">Manage your Sentinel deployments</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for project <- @projects do %>
          <.link
            navigate={~p"/projects/#{project.slug}/nodes"}
            class="bg-base-100 rounded-lg shadow p-6 hover:shadow-lg transition-shadow"
          >
            <h2 class="text-lg font-semibold"><%= project.name %></h2>
            <p class="text-gray-500 text-sm mt-1"><%= project.description || "No description" %></p>
            <div class="mt-4 text-sm text-gray-400">
              <span class="font-mono"><%= project.slug %></span>
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
