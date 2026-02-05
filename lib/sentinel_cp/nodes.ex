defmodule SentinelCp.Nodes do
  @moduledoc """
  The Nodes context handles Sentinel proxy instance management.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Nodes.{DriftEvent, Node, NodeEvent, NodeHeartbeat, NodeRuntimeConfig}

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

  ## Node Events

  @doc """
  Creates a single node event.
  """
  def create_node_event(attrs) do
    %NodeEvent{}
    |> NodeEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple node events in a transaction.
  """
  def create_node_events(events_attrs) when is_list(events_attrs) do
    Repo.transaction(fn ->
      Enum.map(events_attrs, fn attrs ->
        case create_node_event(attrs) do
          {:ok, event} -> event
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Lists recent events for a node, ordered by most recent first.
  """
  def list_node_events(node_id, limit \\ 50) do
    from(e in NodeEvent,
      where: e.node_id == ^node_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Cleans up old event records.
  Keeps only the most recent records per node.
  """
  def cleanup_old_events(keep_count \\ 500) do
    subquery =
      from(e in NodeEvent,
        select: %{
          id: e.id,
          row_num: over(row_number(), partition_by: e.node_id, order_by: [desc: e.inserted_at])
        }
      )

    from(e in NodeEvent,
      join: s in subquery(subquery),
      on: e.id == s.id,
      where: s.row_num > ^keep_count
    )
    |> Repo.delete_all()
  end

  ## Node Runtime Config

  @doc """
  Upserts the runtime config for a node.
  Computes a SHA256 hash of the KDL content.
  """
  def upsert_runtime_config(node_id, config_kdl) do
    config_hash =
      :crypto.hash(:sha256, config_kdl)
      |> Base.encode16(case: :lower)

    attrs = %{
      node_id: node_id,
      config_kdl: config_kdl,
      config_hash: config_hash
    }

    %NodeRuntimeConfig{}
    |> NodeRuntimeConfig.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:config_kdl, :config_hash, :updated_at]},
      conflict_target: :node_id
    )
  end

  @doc """
  Gets the runtime config for a node.
  """
  def get_runtime_config(node_id) do
    Repo.get_by(NodeRuntimeConfig, node_id: node_id)
  end

  @doc """
  Cleans up old heartbeat records.
  Keeps only the most recent records per node.
  """
  def cleanup_old_heartbeats(keep_count \\ 1000) do
    # This is a simple implementation - for production, consider a more efficient approach
    subquery =
      from(h in NodeHeartbeat,
        select: %{
          id: h.id,
          row_num: over(row_number(), partition_by: h.node_id, order_by: [desc: h.inserted_at])
        }
      )

    from(h in NodeHeartbeat,
      join: s in subquery(subquery),
      on: h.id == s.id,
      where: s.row_num > ^keep_count
    )
    |> Repo.delete_all()
  end

  ## Drift Detection

  @doc """
  Sets the expected_bundle_id for a list of node IDs.
  """
  def set_expected_bundle_for_nodes(node_ids, bundle_id) when is_list(node_ids) do
    from(n in Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [expected_bundle_id: bundle_id])
  end

  @doc """
  Lists nodes that are drifted (active_bundle_id != expected_bundle_id).
  Only considers online nodes with an expected_bundle_id set.
  """
  def list_drifted_nodes(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id),
      order_by: [asc: n.name]
    )
    |> Repo.all()
  end

  @doc """
  Counts drifted nodes for a project.
  """
  def count_drifted_nodes(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns drift statistics for a project.
  """
  def get_drift_stats(project_id) do
    total_managed =
      from(n in Node,
        where: n.project_id == ^project_id,
        where: not is_nil(n.expected_bundle_id)
      )
      |> Repo.aggregate(:count)

    drifted = count_drifted_nodes(project_id)

    %{
      total_managed: total_managed,
      drifted: drifted,
      in_sync: total_managed - drifted
    }
  end

  @doc """
  Returns drift statistics across multiple projects.
  """
  def get_fleet_drift_stats(project_ids) when is_list(project_ids) do
    if project_ids == [] do
      %{total_managed: 0, drifted: 0, in_sync: 0}
    else
      total_managed =
        from(n in Node,
          where: n.project_id in ^project_ids,
          where: not is_nil(n.expected_bundle_id)
        )
        |> Repo.aggregate(:count)

      drifted =
        from(n in Node,
          where: n.project_id in ^project_ids,
          where: n.status == "online",
          where: not is_nil(n.expected_bundle_id),
          where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
        )
        |> Repo.aggregate(:count)

      %{
        total_managed: total_managed,
        drifted: drifted,
        in_sync: total_managed - drifted
      }
    end
  end

  @doc """
  Checks if a node is drifted.
  """
  def node_drifted?(%Node{expected_bundle_id: nil}), do: false

  def node_drifted?(%Node{expected_bundle_id: expected, active_bundle_id: active}) do
    expected != active
  end

  ## Drift Events

  @doc """
  Gets a drift event by ID.
  """
  def get_drift_event(id), do: Repo.get(DriftEvent, id)

  @doc """
  Gets a drift event by ID, raises if not found.
  """
  def get_drift_event!(id), do: Repo.get!(DriftEvent, id)

  @doc """
  Creates a drift event.
  """
  def create_drift_event(attrs) do
    %DriftEvent{}
    |> DriftEvent.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Resolves a drift event with the given resolution.
  """
  def resolve_drift_event(%DriftEvent{} = event, resolution) do
    event
    |> DriftEvent.resolve_changeset(resolution)
    |> Repo.update()
  end

  @doc """
  Gets the active (unresolved) drift event for a node.
  """
  def get_active_drift_event(node_id) do
    from(d in DriftEvent,
      where: d.node_id == ^node_id,
      where: is_nil(d.resolved_at),
      order_by: [desc: d.detected_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists drift events for a project.
  """
  def list_drift_events(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    include_resolved = Keyword.get(opts, :include_resolved, true)

    query =
      from(d in DriftEvent,
        where: d.project_id == ^project_id,
        order_by: [desc: d.detected_at],
        limit: ^limit,
        preload: [:node]
      )

    query =
      if include_resolved do
        query
      else
        where(query, [d], is_nil(d.resolved_at))
      end

    Repo.all(query)
  end

  @doc """
  Returns drift event statistics for a project.
  """
  def get_drift_event_stats(project_id) do
    active =
      from(d in DriftEvent,
        where: d.project_id == ^project_id,
        where: is_nil(d.resolved_at)
      )
      |> Repo.aggregate(:count)

    resolved_today =
      from(d in DriftEvent,
        where: d.project_id == ^project_id,
        where: not is_nil(d.resolved_at),
        where: d.resolved_at >= ^start_of_day()
      )
      |> Repo.aggregate(:count)

    %{
      active: active,
      resolved_today: resolved_today
    }
  end

  @doc """
  Returns drift event statistics across multiple projects.
  """
  def get_fleet_drift_event_stats(project_ids) when is_list(project_ids) do
    if project_ids == [] do
      %{active: 0, resolved_today: 0}
    else
      active =
        from(d in DriftEvent,
          where: d.project_id in ^project_ids,
          where: is_nil(d.resolved_at)
        )
        |> Repo.aggregate(:count)

      resolved_today =
        from(d in DriftEvent,
          where: d.project_id in ^project_ids,
          where: not is_nil(d.resolved_at),
          where: d.resolved_at >= ^start_of_day()
        )
        |> Repo.aggregate(:count)

      %{
        active: active,
        resolved_today: resolved_today
      }
    end
  end

  defp start_of_day do
    DateTime.utc_now()
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  @doc """
  Resolves all active drift events for a node.
  """
  def resolve_node_drift_events(node_id, resolution) do
    from(d in DriftEvent,
      where: d.node_id == ^node_id,
      where: is_nil(d.resolved_at)
    )
    |> Repo.update_all(
      set: [
        resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
        resolution: resolution
      ]
    )
  end
end
