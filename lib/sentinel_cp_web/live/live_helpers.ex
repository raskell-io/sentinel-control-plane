defmodule SentinelCpWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for access control.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias SentinelCp.Accounts

  @doc """
  on_mount hook for LiveView access control.

  Supported actions:
  - `:fetch_current_user` — assigns current user from session
  - `:require_admin` — requires admin role, redirects otherwise
  """
  def on_mount(action, params, session, socket)

  def on_mount(:fetch_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user && socket.assigns.current_user.role == "admin" do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You do not have permission to access this page.")
        |> redirect(to: "/projects")

      {:halt, socket}
    end
  end

  defp assign_current_user(socket, session) do
    case session["user_token"] do
      nil ->
        assign(socket, :current_user, nil)

      token ->
        user = Accounts.get_user_by_session_token(token)
        assign(socket, :current_user, user)
    end
  end
end
