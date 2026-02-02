defmodule SentinelCpWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for access control.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias SentinelCp.Accounts

  @doc """
  on_mount hook that requires admin role.

  Usage in LiveView:

      on_mount {SentinelCpWeb.LiveHelpers, :require_admin}
  """
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
