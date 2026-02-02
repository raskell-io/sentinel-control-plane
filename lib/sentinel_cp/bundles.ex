defmodule SentinelCp.Bundles do
  @moduledoc """
  The Bundles context handles bundle lifecycle management.

  Bundles are immutable, content-addressed configuration artifacts that are
  compiled from KDL config, stored in S3/MinIO, and distributed to nodes.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Bundles.Bundle

  @doc """
  Creates a bundle and enqueues compilation.
  """
  def create_bundle(attrs) do
    changeset = Bundle.create_changeset(%Bundle{}, attrs)

    case Repo.insert(changeset) do
      {:ok, bundle} ->
        enqueue_compilation(bundle)
        {:ok, bundle}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Lists bundles for a project, ordered by most recent first.
  """
  def list_bundles(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(b in Bundle,
        where: b.project_id == ^project_id,
        order_by: [desc: b.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      Enum.reduce(opts, query, fn
        {:status, status}, q -> where(q, [b], b.status == ^status)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a bundle by ID.
  """
  def get_bundle(id), do: Repo.get(Bundle, id)

  @doc """
  Gets a bundle by ID, raises if not found.
  """
  def get_bundle!(id), do: Repo.get!(Bundle, id)

  @doc """
  Gets the latest compiled bundle for a project.
  """
  def get_latest_bundle(project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id and b.status == "compiled",
      order_by: [desc: b.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Updates a bundle's compilation results.
  """
  def update_compilation(bundle, attrs) do
    bundle
    |> Bundle.compilation_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a bundle as a specific status.
  """
  def update_status(bundle, status) do
    bundle
    |> Bundle.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Assigns a bundle to one or more nodes as their staged bundle.
  """
  def assign_bundle_to_nodes(bundle, node_ids) when is_list(node_ids) do
    {count, _} =
      from(n in SentinelCp.Nodes.Node,
        where: n.id in ^node_ids and n.project_id == ^bundle.project_id
      )
      |> Repo.update_all(set: [staged_bundle_id: bundle.id])

    {:ok, count}
  end

  @doc """
  Counts bundles by status for a project.
  """
  def count_bundles(project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id,
      group_by: b.status,
      select: {b.status, count(b.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Deletes a bundle (only if pending or failed).
  """
  def delete_bundle(%Bundle{status: status} = bundle) when status in ["pending", "failed"] do
    Repo.delete(bundle)
  end

  def delete_bundle(%Bundle{}) do
    {:error, :cannot_delete_active_bundle}
  end

  # Enqueue compilation via Oban
  defp enqueue_compilation(bundle) do
    %{bundle_id: bundle.id}
    |> SentinelCp.Bundles.CompileWorker.new()
    |> Oban.insert()
  end
end
