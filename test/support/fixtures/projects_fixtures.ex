defmodule SentinelCp.ProjectsFixtures do
  @moduledoc """
  Test helpers for creating Projects entities.
  """

  def unique_project_name, do: "project-#{System.unique_integer([:positive])}"

  def valid_project_attributes(attrs \\ %{}) do
    org = attrs[:org] || SentinelCp.OrgsFixtures.org_fixture()

    Enum.into(attrs, %{
      name: unique_project_name(),
      description: "A test project",
      org_id: org.id
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
