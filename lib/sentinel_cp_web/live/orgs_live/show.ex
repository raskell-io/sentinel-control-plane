defmodule SentinelCpWeb.OrgsLive.Show do
  @moduledoc """
  LiveView for showing org details and managing members.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.Orgs

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case Orgs.get_org_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      org ->
        members = Orgs.list_members(org)
        user_role = Orgs.get_user_role(org.id, socket.assigns.current_user.id)

        {:ok,
         assign(socket,
           page_title: org.name,
           org: org,
           members: members,
           user_role: user_role
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="text-sm breadcrumbs mb-4">
        <ul>
          <li><.link navigate={~p"/orgs"}>Organizations</.link></li>
          <li>{@org.name}</li>
        </ul>
      </div>

      <div class="flex items-center gap-4 mb-6">
        <h1 class="text-2xl font-bold">{@org.name}</h1>
        <span class="badge badge-ghost font-mono">{@org.slug}</span>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- Quick Links --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-lg">Quick Links</h2>
            <div class="flex flex-col gap-2">
              <.link navigate={~p"/orgs/#{@org.slug}/projects"} class="link link-primary">
                Projects
              </.link>
            </div>
          </div>
        </div>

        <%!-- Members --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-lg">Members</h2>
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Email</th>
                  <th>Role</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={membership <- @members}>
                  <td>{membership.user.email}</td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      membership.role == "admin" && "badge-primary",
                      membership.role == "operator" && "badge-warning",
                      membership.role == "reader" && "badge-ghost"
                    ]}>
                      {membership.role}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
