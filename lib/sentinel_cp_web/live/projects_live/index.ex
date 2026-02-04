defmodule SentinelCpWeb.ProjectsLive.Index do
  @moduledoc """
  LiveView for listing and managing projects.
  Supports both org-scoped (/orgs/:org_slug/projects) and legacy (/projects) routes.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Projects, Orgs}

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
         |> assign(:show_form, false)
         |> assign(:editing_id, nil)
         |> assign(:page_title, "Projects — #{org.name}")}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  def handle_event("create_project", %{"name" => name, "description" => description}, socket) do
    org = socket.assigns.org

    case Projects.create_project(%{name: name, description: description, org_id: org.id}) do
      {:ok, project} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "project", project.id,
          org_id: org.id,
          project_id: project.id
        )

        projects = Projects.list_projects(org_id: org.id)

        {:noreply,
         socket
         |> assign(projects: projects, show_form: false)
         |> put_flash(:info, "Project created.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create project: #{format_errors(changeset)}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    {:noreply, assign(socket, editing_id: project.id, edit_name: project.name, edit_description: project.description || "")}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("update_project", %{"name" => name, "description" => description}, socket) do
    project = Projects.get_project!(socket.assigns.editing_id)
    org = socket.assigns.org

    case Projects.update_project(project, %{name: name, description: description}) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "project", updated.id,
          org_id: org.id,
          project_id: updated.id
        )

        projects = Projects.list_projects(org_id: org.id)

        {:noreply,
         socket
         |> assign(projects: projects, editing_id: nil)
         |> put_flash(:info, "Project updated.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update project: #{format_errors(changeset)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    org = socket.assigns.org

    case Projects.delete_project(project) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "project", project.id,
          org_id: org.id,
          project_id: project.id
        )

        projects = Projects.list_projects(org_id: org.id)

        {:noreply,
         socket
         |> assign(projects: projects)
         |> put_flash(:info, "Project deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete project.")}
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

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
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
        <button class="btn btn-primary btn-sm" phx-click="toggle_form">
          New Project
        </button>
      </div>

      <div :if={@show_form} class="card bg-base-200 mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">Create Project</h2>
          <form phx-submit="create_project" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                class="input input-bordered w-full max-w-xs"
                placeholder="e.g. my-project"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <textarea
                name="description"
                rows="3"
                class="textarea textarea-bordered w-full max-w-md"
                placeholder="Optional description"
              ></textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for project <- @projects do %>
          <%= if @editing_id == project.id do %>
            <div class="bg-base-100 rounded-lg shadow p-6">
              <form phx-submit="update_project" class="space-y-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Name</span></label>
                  <input
                    type="text"
                    name="name"
                    required
                    value={@edit_name}
                    class="input input-bordered w-full"
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Description</span></label>
                  <textarea
                    name="description"
                    rows="3"
                    class="textarea textarea-bordered w-full"
                  >{@edit_description}</textarea>
                </div>
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Save</button>
                  <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          <% else %>
            <div class="bg-base-100 rounded-lg shadow p-6 relative group">
              <.link
                navigate={~p"/orgs/#{@org.slug}/projects/#{project.slug}/nodes"}
                class="block hover:opacity-80"
              >
                <h2 class="text-lg font-semibold">{project.name}</h2>
                <p class="text-gray-500 text-sm mt-1">{project.description || "No description"}</p>
                <div class="mt-4 text-sm text-gray-400">
                  <span class="font-mono">{project.slug}</span>
                </div>
              </.link>
              <div class="absolute top-4 right-4 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  phx-click="edit"
                  phx-value-id={project.id}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={project.id}
                  data-confirm="Are you sure you want to delete this project?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </div>
            </div>
          <% end %>
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
