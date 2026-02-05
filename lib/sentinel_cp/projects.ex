defmodule SentinelCp.Projects do
  @moduledoc """
  The Projects context handles project (tenant) management.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Projects.Project

  @doc """
  Returns the list of projects, optionally scoped to an org.
  """
  def list_projects(opts \\ []) do
    query = from(p in Project, order_by: [asc: p.name])

    query =
      case Keyword.get(opts, :org_id) do
        nil -> query
        org_id -> where(query, [p], p.org_id == ^org_id)
      end

    Repo.all(query)
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
  Gets a single project by GitHub repository name (e.g. "owner/repo").
  """
  def get_project_by_github_repo(repo) when is_binary(repo) do
    Repo.get_by(Project, github_repo: repo)
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

  @doc """
  Lists all projects that have drift alert thresholds configured.
  """
  def list_projects_with_drift_alerts do
    from(p in Project)
    |> Repo.all()
    |> Enum.filter(fn project ->
      Project.drift_alert_threshold(project) != nil ||
        Project.drift_alert_node_count(project) != nil
    end)
  end
end
