defmodule SentinelCpWeb.OrgsLive.Index do
  @moduledoc """
  LiveView for listing organizations the current user belongs to.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.Orgs

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    org_memberships = Orgs.list_user_orgs(user.id)

    {:ok,
     socket
     |> assign(:org_memberships, org_memberships)
     |> assign(:page_title, "Organizations")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">Organizations</h1>
          <p class="text-gray-500 mt-1">Select an organization to manage</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for {org, role} <- @org_memberships do %>
          <.link
            navigate={~p"/orgs/#{org.slug}/projects"}
            class="bg-base-100 rounded-lg shadow p-6 hover:shadow-lg transition-shadow"
          >
            <div class="flex items-center gap-2">
              <h2 class="text-lg font-semibold">{org.name}</h2>
              <span class="badge badge-sm badge-ghost">{role}</span>
            </div>
            <div class="mt-4 text-sm text-gray-400">
              <span class="font-mono">{org.slug}</span>
            </div>
          </.link>
        <% end %>
      </div>

      <%= if Enum.empty?(@org_memberships) do %>
        <div class="bg-base-100 rounded-lg shadow p-8 text-center text-gray-500">
          <p>You are not a member of any organizations.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
