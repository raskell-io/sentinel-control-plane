defmodule SentinelCpWeb.OrgsLiveTest do
  use SentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SentinelCp.AccountsFixtures
  import SentinelCp.OrgsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "OrgsLive.Index" do
    test "renders orgs list page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/orgs")
      assert html =~ "Organizations"
    end

    test "shows user's organizations", %{conn: conn, user: user} do
      {org, _} = org_with_owner_fixture(%{user: user})
      {:ok, _view, html} = live(conn, ~p"/orgs")
      assert html =~ org.name
    end
  end

  describe "OrgsLive.Show" do
    test "renders org detail page", %{conn: conn} do
      org = org_fixture()
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ org.name
    end
  end
end
