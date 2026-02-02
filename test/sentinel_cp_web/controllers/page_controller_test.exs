defmodule SentinelCpWeb.PageControllerTest do
  use SentinelCpWeb.ConnCase

  import SentinelCp.AccountsFixtures

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/login"
  end

  test "GET / redirects to projects when authenticated", %{conn: conn} do
    user = user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == "/projects"
  end
end
