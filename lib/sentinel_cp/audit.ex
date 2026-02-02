defmodule SentinelCp.Audit do
  @moduledoc """
  The Audit context handles audit logging for all mutations.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Audit.AuditLog

  @audit_topic "audit_logs"

  @doc """
  Logs an audit event and broadcasts it via PubSub.
  """
  def log(attrs) do
    result =
      %AuditLog{}
      |> AuditLog.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, log_entry} ->
        Phoenix.PubSub.broadcast(SentinelCp.PubSub, @audit_topic, {:audit_log_created, log_entry})
        {:ok, log_entry}

      error ->
        error
    end
  end

  @doc """
  Logs an audit event for a user action.
  """
  def log_user_action(user, action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "user",
      actor_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: opts[:project_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Logs an audit event for an API key action.
  """
  def log_api_key_action(api_key, action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "api_key",
      actor_id: api_key.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: api_key.project_id || opts[:project_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Logs an audit event for a node action.
  """
  def log_node_action(node, action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "node",
      actor_id: node.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: node.project_id,
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Logs an audit event for a system action.
  """
  def log_system_action(action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "system",
      actor_id: nil,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: opts[:project_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Lists audit logs for a project with filtering and pagination.

  ## Options

    * `:limit` - max results (default 25)
    * `:offset` - offset for pagination (default 0)
    * `:action` - filter by action
    * `:resource_type` - filter by resource type
    * `:actor_type` - filter by actor type

  Returns `{entries, total_count}`.
  """
  def list_audit_logs(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from(a in AuditLog,
        where: a.project_id == ^project_id,
        order_by: [desc: a.inserted_at]
      )

    filtered_query = apply_filters(base_query, opts)

    total = Repo.aggregate(filtered_query, :count)

    entries =
      filtered_query
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {entries, total}
  end

  @doc """
  Lists all audit logs across projects with filtering and pagination.

  Same options as `list_audit_logs/2` plus:
    * `:date_from` - filter from date (DateTime)
    * `:date_to` - filter to date (DateTime)

  Returns `{entries, total_count}`.
  """
  def list_all_audit_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from(a in AuditLog,
        order_by: [desc: a.inserted_at]
      )

    filtered_query = apply_filters(base_query, opts)

    total = Repo.aggregate(filtered_query, :count)

    entries =
      filtered_query
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {entries, total}
  end

  @doc """
  Lists audit logs for a specific resource.
  """
  def list_audit_logs_for_resource(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(a in AuditLog,
      where: a.resource_type == ^resource_type and a.resource_id == ^resource_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Subscribes to real-time audit log updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(SentinelCp.PubSub, @audit_topic)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:action, action}, q when is_binary(action) ->
        where(q, [a], a.action == ^action)

      {:resource_type, type}, q when is_binary(type) ->
        where(q, [a], a.resource_type == ^type)

      {:actor_type, type}, q when is_binary(type) ->
        where(q, [a], a.actor_type == ^type)

      {:date_from, %DateTime{} = dt}, q ->
        where(q, [a], a.inserted_at >= ^dt)

      {:date_to, %DateTime{} = dt}, q ->
        where(q, [a], a.inserted_at <= ^dt)

      _, q ->
        q
    end)
  end
end
