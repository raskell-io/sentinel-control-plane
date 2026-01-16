defmodule SentinelCp.Projects do
  @moduledoc """
  The Projects context handles project (tenant) management.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Projects.Project

  @doc """
  Returns the list of projects.
  """
  def list_projects do
    Repo.all(from p in Project, order_by: [asc: p.name])
  end

  @doc """
  Gets a single project by ID.
  """
  def get_project(id), do: Repo.get(Project, id)

  @doc """
  Gets a single project by ID, raises if not found.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Gets a single project by slug.
  """
  def get_project_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Project, slug: slug)
  end

  @doc """
  Creates a project.
  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.create_changeset(project, attrs)
  end
end
