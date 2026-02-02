defmodule SentinelCp.ProjectsFixtures do
  @moduledoc """
  Test helpers for creating Projects entities.
  """

  def unique_project_name, do: "project-#{System.unique_integer([:positive])}"

  def valid_project_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_project_name(),
      description: "A test project"
    })
  end

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> valid_project_attributes()
      |> SentinelCp.Projects.create_project()

    project
  end
end
