defmodule SentinelCp.Audit do
  @moduledoc """
  The Audit context handles audit logging for all mutations.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Audit.AuditLog

  @doc """
  Logs an audit event.
  """
  def log(attrs) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
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
  Lists audit logs for a project.
  """
  def list_audit_logs(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(a in AuditLog,
        where: a.project_id == ^project_id,
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      Enum.reduce(opts, query, fn
        {:action, action}, q -> where(q, [a], a.action == ^action)
        {:resource_type, type}, q -> where(q, [a], a.resource_type == ^type)
        {:actor_type, type}, q -> where(q, [a], a.actor_type == ^type)
        _, q -> q
      end)

    Repo.all(query)
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
end
