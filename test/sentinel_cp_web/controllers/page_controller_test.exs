defmodule SentinelCpWeb.PageControllerTest do
  use SentinelCpWeb.ConnCase

  test "GET / redirects to projects", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/projects"
  end
end
