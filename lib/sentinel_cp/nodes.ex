defmodule SentinelCp.Nodes do
  @moduledoc """
  The Nodes context handles Sentinel proxy instance management.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Nodes.{Node, NodeHeartbeat}

  @stale_threshold_seconds 120

  ## Node Management

  @doc """
  Lists all nodes for a project.
  """
  def list_nodes(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      order_by: [asc: n.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists nodes with optional filters.
  """
  def list_nodes(project_id, opts) do
    query = from(n in Node, where: n.project_id == ^project_id)

    query =
      Enum.reduce(opts, query, fn
        {:status, status}, q -> where(q, [n], n.status == ^status)
        {:labels, labels}, q -> filter_by_labels(q, labels)
        _, q -> q
      end)

    query
    |> order_by([n], asc: n.name)
    |> Repo.all()
  end

  defp filter_by_labels(query, labels) when is_map(labels) do
    Enum.reduce(labels, query, fn {key, value}, q ->
      # JSON containment check - works for both SQLite and Postgres
      where(q, [n], fragment("json_extract(?, ?) = ?", n.labels, ^"$.#{key}", ^value))
    end)
  end

  @doc """
  Gets a single node by ID.
  """
  def get_node(id), do: Repo.get(Node, id)

  @doc """
  Gets a single node by ID, raises if not found.
  """
  def get_node!(id), do: Repo.get!(Node, id)

  @doc """
  Gets a node by project and name.
  """
  def get_node_by_name(project_id, name) do
    Repo.get_by(Node, project_id: project_id, name: name)
  end

  @doc """
  Gets a node by its key hash.
  """
  def get_node_by_key(node_key) when is_binary(node_key) do
    key_hash = Node.hash_node_key(node_key)
    Repo.get_by(Node, node_key_hash: key_hash)
  end

  @doc """
  Registers a new node. Returns {:ok, node_with_key} or {:error, changeset}.
  The node_key is only available on the returned node immediately after registration.
  """
  def register_node(attrs) do
    %Node{}
    |> Node.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records a heartbeat from a node.
  Updates the node's last_seen_at and optionally stores historical heartbeat data.
  """
  def record_heartbeat(%Node{} = node, attrs \\ %{}) do
    Repo.transaction(fn ->
      # Update node
      {:ok, updated_node} =
        node
        |> Node.heartbeat_changeset(attrs)
        |> Repo.update()

      # Record heartbeat history
      %NodeHeartbeat{}
      |> NodeHeartbeat.changeset(Map.merge(attrs, %{node_id: node.id}))
      |> Repo.insert!()

      updated_node
    end)
  end

  @doc """
  Authenticates a node by its key.
  Returns {:ok, node} if valid, {:error, :invalid_key} otherwise.
  """
  def authenticate_node(node_key) when is_binary(node_key) do
    case get_node_by_key(node_key) do
      nil -> {:error, :invalid_key}
      node -> {:ok, node}
    end
  end

  @doc """
  Marks stale nodes as offline.
  A node is stale if it hasn't sent a heartbeat within the threshold.
  """
  def mark_stale_nodes_offline(threshold_seconds \\ @stale_threshold_seconds) do
    cutoff = DateTime.utc_now() |> DateTime.add(-threshold_seconds, :second)

    from(n in Node,
      where: n.status == "online" and n.last_seen_at < ^cutoff
    )
    |> Repo.update_all(set: [status: "offline"])
  end

  @doc """
  Updates a node's labels.
  """
  def update_node_labels(%Node{} = node, labels) do
    node
    |> Node.labels_changeset(labels)
    |> Repo.update()
  end

  @doc """
  Deletes a node.
  """
  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  ## Node Stats

  @doc """
  Returns node counts by status for a project.
  """
  def get_node_stats(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      group_by: n.status,
      select: {n.status, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the total number of nodes for a project.
  """
  def count_nodes(project_id) do
    from(n in Node, where: n.project_id == ^project_id)
    |> Repo.aggregate(:count)
  end

  ## Heartbeat History

  @doc """
  Lists recent heartbeats for a node.
  """
  def list_recent_heartbeats(node_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    list_node_heartbeats(node_id, limit)
  end

  @doc """
  Lists recent heartbeats for a node.
  """
  def list_node_heartbeats(node_id, limit \\ 100) do
    from(h in NodeHeartbeat,
      where: h.node_id == ^node_id,
      order_by: [desc: h.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Cleans up old heartbeat records.
  Keeps only the most recent records per node.
  """
  def cleanup_old_heartbeats(keep_count \\ 1000) do
    # This is a simple implementation - for production, consider a more efficient approach
    subquery =
      from(h in NodeHeartbeat,
        select: %{id: h.id, row_num: over(row_number(), partition_by: h.node_id, order_by: [desc: h.inserted_at])}
      )

    from(h in NodeHeartbeat,
      join: s in subquery(subquery),
      on: h.id == s.id,
      where: s.row_num > ^keep_count
    )
    |> Repo.delete_all()
  end
end
