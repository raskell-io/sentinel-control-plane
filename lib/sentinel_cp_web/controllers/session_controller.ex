defmodule SentinelCpWeb.SessionController do
  use SentinelCpWeb, :controller

  alias SentinelCp.Accounts
  alias SentinelCpWeb.Plugs.Auth

  def create(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      Auth.log_in_user(conn, user)
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: "/login")
    end
  end

  def delete(conn, _params) do
    Auth.log_out_user(conn)
  end
end
