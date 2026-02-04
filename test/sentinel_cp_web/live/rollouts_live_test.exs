defmodule SentinelCpWeb.RolloutsLiveTest do
  use SentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SentinelCp.AccountsFixtures
  import SentinelCp.ProjectsFixtures
  import SentinelCp.RolloutsFixtures
  import SentinelCp.NodesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "RolloutsLive.Index" do
    test "renders rollouts list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts")
      assert html =~ "Rollouts"
    end

    test "shows existing rollouts", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      _rollout = rollout_fixture(%{project: project, bundle: bundle})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts")
      assert html =~ "pending"
    end
  end

  describe "RolloutsLive.Show" do
    test "renders rollout detail page", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts/#{rollout.id}")
      assert html =~ "pending"
    end
  end
end
