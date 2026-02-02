defmodule SentinelCp.ProjectsTest do
  use SentinelCp.DataCase

  alias SentinelCp.Projects
  alias SentinelCp.Projects.Project

  import SentinelCp.ProjectsFixtures

  describe "create_project/1" do
    test "creates project with valid attributes" do
      assert {:ok, %Project{} = project} = Projects.create_project(%{name: "My Project"})
      assert project.name == "My Project"
      assert project.slug == "my-project"
    end

    test "auto-generates slug from name" do
      assert {:ok, project} = Projects.create_project(%{name: "Hello World App"})
      assert project.slug == "hello-world-app"
    end

    test "returns error for blank name" do
      assert {:error, changeset} = Projects.create_project(%{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for duplicate slug" do
      assert {:ok, _} = Projects.create_project(%{name: "Duplicate"})
      assert {:error, changeset} = Projects.create_project(%{name: "Duplicate"})
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_project_by_slug/1" do
    test "returns project by slug" do
      project = project_fixture()
      found = Projects.get_project_by_slug(project.slug)
      assert found.id == project.id
    end

    test "returns nil for unknown slug" do
      refute Projects.get_project_by_slug("nonexistent")
    end
  end

  describe "list_projects/0" do
    test "returns all projects ordered by name" do
      _p1 = project_fixture(%{name: "Bravo"})
      _p2 = project_fixture(%{name: "Alpha"})

      projects = Projects.list_projects()
      names = Enum.map(projects, & &1.name)
      assert Enum.find_index(names, &(&1 == "Alpha")) < Enum.find_index(names, &(&1 == "Bravo"))
    end
  end

  describe "update_project/2" do
    test "updates project attributes" do
      project = project_fixture()
      assert {:ok, updated} = Projects.update_project(project, %{description: "updated"})
      assert updated.description == "updated"
    end
  end

  describe "delete_project/1" do
    test "deletes a project" do
      project = project_fixture()
      assert {:ok, _} = Projects.delete_project(project)
      refute Projects.get_project(project.id)
    end
  end
end
