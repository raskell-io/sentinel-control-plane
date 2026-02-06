defmodule SentinelCp.Services do
  @moduledoc """
  The Services context manages proxy service definitions.

  Services are structured representations of proxy routes that can be
  used to generate KDL configuration for bundles.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Services.{Service, ProjectConfig}

  ## Services

  @doc """
  Lists services for a project, ordered by position.
  """
  def list_services(project_id, opts \\ []) do
    query =
      from(s in Service,
        where: s.project_id == ^project_id,
        order_by: [asc: s.position, asc: s.inserted_at]
      )

    query =
      Enum.reduce(opts, query, fn
        {:enabled, enabled}, q -> where(q, [s], s.enabled == ^enabled)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a single service by ID.
  """
  def get_service(id), do: Repo.get(Service, id)

  @doc """
  Gets a single service by ID, raises if not found.
  """
  def get_service!(id), do: Repo.get!(Service, id)

  @doc """
  Creates a service.
  """
  def create_service(attrs) do
    %Service{}
    |> Service.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a service.
  """
  def update_service(%Service{} = service, attrs) do
    service
    |> Service.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a service.
  """
  def delete_service(%Service{} = service) do
    Repo.delete(service)
  end

  @doc """
  Batch updates service positions.

  Accepts a list of `{service_id, position}` tuples.
  """
  def reorder_services(project_id, id_position_pairs) do
    Repo.transaction(fn ->
      for {id, position} <- id_position_pairs do
        from(s in Service,
          where: s.id == ^id and s.project_id == ^project_id
        )
        |> Repo.update_all(set: [position: position])
      end

      :ok
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking service changes.
  """
  def change_service(%Service{} = service, attrs \\ %{}) do
    Service.update_changeset(service, attrs)
  end

  ## Project Config

  @doc """
  Gets or creates the project config for a project.
  """
  def get_or_create_project_config(project_id) do
    case Repo.get_by(ProjectConfig, project_id: project_id) do
      nil ->
        %ProjectConfig{}
        |> ProjectConfig.changeset(%{project_id: project_id})
        |> Repo.insert()

      config ->
        {:ok, config}
    end
  end

  @doc """
  Updates the project config.
  """
  def update_project_config(%ProjectConfig{} = config, attrs) do
    config
    |> ProjectConfig.changeset(attrs)
    |> Repo.update()
  end
end
