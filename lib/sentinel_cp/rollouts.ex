defmodule SentinelCp.Rollouts do
  @moduledoc """
  The Rollouts context handles bundle deployment orchestration.

  Rollouts progress through batched steps, assigning bundles to target nodes
  with health gates and support for pause/resume/cancel/rollback.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Rollouts.{Rollout, RolloutStep, NodeBundleStatus, TickWorker}
  alias SentinelCp.{Bundles, Nodes}

  ## Rollout CRUD

  @doc """
  Creates a rollout. Validates that the bundle is compiled.
  """
  def create_rollout(attrs) do
    changeset = Rollout.create_changeset(%Rollout{}, attrs)

    with {:ok, changeset} <- validate_bundle_compiled(changeset),
         {:ok, rollout} <- Repo.insert(changeset) do
      {:ok, rollout}
    end
  end

  @doc """
  Lists rollouts for a project, ordered by most recent first.
  """
  def list_rollouts(project_id, opts \\ []) do
    query =
      from(r in Rollout,
        where: r.project_id == ^project_id,
        order_by: [desc: r.inserted_at]
      )

    query =
      Enum.reduce(opts, query, fn
        {:state, state}, q -> where(q, [r], r.state == ^state)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a rollout by ID.
  """
  def get_rollout(id), do: Repo.get(Rollout, id)

  @doc """
  Gets a rollout by ID, raises if not found.
  """
  def get_rollout!(id), do: Repo.get!(Rollout, id)

  @doc """
  Gets a rollout with steps and node_bundle_statuses preloaded.
  """
  def get_rollout_with_details(id) do
    Rollout
    |> Repo.get(id)
    |> Repo.preload(steps: from(s in RolloutStep, order_by: s.step_index))
    |> Repo.preload(:node_bundle_statuses)
  end

  @doc """
  Enqueues a tick job for the given rollout.
  Call this after plan_rollout or resume_rollout to start/continue processing.
  """
  def schedule_tick(rollout_id) do
    enqueue_tick(rollout_id)
  end

  ## Rollout Lifecycle

  @doc """
  Plans a rollout: resolves target nodes, creates batched steps and
  NodeBundleStatus records, and transitions to running.

  The caller should call `schedule_tick/1` after to begin processing.
  """
  def plan_rollout(%Rollout{state: "pending"} = rollout) do
    node_ids = resolve_target_nodes(rollout.project_id, rollout.target_selector)

    if node_ids == [] do
      {:error, :no_target_nodes}
    else
      batches = chunk_into_batches(node_ids, rollout.strategy, rollout.batch_size)

      Repo.transaction(fn ->
        # Create steps
        steps =
          batches
          |> Enum.with_index()
          |> Enum.map(fn {batch_node_ids, index} ->
            {:ok, step} =
              %RolloutStep{}
              |> RolloutStep.create_changeset(%{
                rollout_id: rollout.id,
                step_index: index,
                node_ids: batch_node_ids
              })
              |> Repo.insert()

            step
          end)

        # Create NodeBundleStatus records for all target nodes
        for node_id <- node_ids do
          %NodeBundleStatus{}
          |> NodeBundleStatus.create_changeset(%{
            node_id: node_id,
            rollout_id: rollout.id,
            bundle_id: rollout.bundle_id
          })
          |> Repo.insert!()
        end

        # Transition to running
        {:ok, updated} =
          rollout
          |> Rollout.state_changeset("running")
          |> Repo.update()

        # Enqueue first tick
        enqueue_tick(rollout.id)

        {updated, steps}
      end)
    end
  end

  def plan_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Core state machine driver. Called by the TickWorker on each tick.
  """
  def tick_rollout(%Rollout{state: "running"} = rollout) do
    rollout = Repo.preload(rollout, steps: from(s in RolloutStep, order_by: s.step_index))

    # Find active step (running or verifying)
    active_step =
      Enum.find(rollout.steps, fn s -> s.state in ~w(running verifying) end)

    cond do
      active_step && active_step.state == "running" ->
        check_step_running(rollout, active_step)

      active_step && active_step.state == "verifying" ->
        check_step_verifying(rollout, active_step)

      true ->
        # No active step — start next pending step
        next_step = Enum.find(rollout.steps, fn s -> s.state == "pending" end)

        if next_step do
          start_step(rollout, next_step)
        else
          # All steps completed
          complete_rollout(rollout)
        end
    end
  end

  def tick_rollout(%Rollout{}), do: {:ok, :not_running}

  @doc """
  Pauses a running rollout.
  """
  def pause_rollout(%Rollout{state: "running"} = rollout) do
    rollout
    |> Rollout.state_changeset("paused")
    |> Repo.update()
  end

  def pause_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Resumes a paused rollout and reschedules the tick.
  """
  def resume_rollout(%Rollout{state: "paused"} = rollout) do
    case rollout |> Rollout.state_changeset("running") |> Repo.update() do
      {:ok, updated} ->
        enqueue_tick(rollout.id)
        {:ok, updated}

      error ->
        error
    end
  end

  def resume_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Cancels a running or paused rollout.
  """
  def cancel_rollout(%Rollout{state: state} = rollout) when state in ~w(running paused) do
    rollout
    |> Rollout.state_changeset("cancelled")
    |> Repo.update()
  end

  def cancel_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Cancels the rollout and reverts affected nodes' staged_bundle_id
  back to their active_bundle_id.
  """
  def rollback_rollout(%Rollout{state: state} = rollout) when state in ~w(running paused) do
    Repo.transaction(fn ->
      # Cancel the rollout
      {:ok, cancelled} =
        rollout
        |> Rollout.state_changeset("cancelled")
        |> Repo.update()

      # Revert staged_bundle_id for affected nodes
      node_ids = get_rollout_node_ids(rollout.id)

      if node_ids != [] do
        from(n in Nodes.Node,
          where: n.id in ^node_ids,
          where: n.staged_bundle_id == ^rollout.bundle_id
        )
        |> Repo.update_all(set: [staged_bundle_id: nil])
      end

      cancelled
    end)
  end

  def rollback_rollout(%Rollout{}), do: {:error, :invalid_state}

  ## Queries

  @doc """
  Returns progress counts for a rollout.
  """
  def get_rollout_progress(rollout_id) do
    statuses =
      from(nbs in NodeBundleStatus,
        where: nbs.rollout_id == ^rollout_id,
        group_by: nbs.state,
        select: {nbs.state, count(nbs.id)}
      )
      |> Repo.all()
      |> Map.new()

    total = Enum.reduce(statuses, 0, fn {_state, count}, acc -> acc + count end)
    active = Map.get(statuses, "active", 0)
    failed = Map.get(statuses, "failed", 0)
    pending = total - active - failed

    %{total: total, pending: pending, active: active, failed: failed}
  end

  @doc """
  Resolves target nodes based on selector type.
  """
  def resolve_target_nodes(project_id, %{"type" => "all"}) do
    from(n in Nodes.Node, where: n.project_id == ^project_id, select: n.id)
    |> Repo.all()
  end

  def resolve_target_nodes(project_id, %{"type" => "labels", "labels" => labels}) do
    query = from(n in Nodes.Node, where: n.project_id == ^project_id, select: n.id)

    query =
      Enum.reduce(labels, query, fn {key, value}, q ->
        where(q, [n], fragment("json_extract(?, ?) = ?", n.labels, ^"$.#{key}", ^value))
      end)

    Repo.all(query)
  end

  def resolve_target_nodes(_project_id, %{"type" => "node_ids", "node_ids" => node_ids}) do
    node_ids
  end

  def resolve_target_nodes(_project_id, _selector), do: []

  ## Private — Tick Logic

  defp start_step(rollout, step) do
    # Re-validate bundle is still compiled (could have been revoked since rollout creation)
    bundle = Bundles.get_bundle!(rollout.bundle_id)

    if bundle.status != "compiled" do
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("failed",
          error: %{"reason" => "bundle_revoked", "bundle_id" => rollout.bundle_id}
        )
        |> Repo.update()

      {:ok, _rollout} =
        rollout
        |> Rollout.state_changeset("failed",
          error: %{"reason" => "bundle_revoked", "bundle_id" => rollout.bundle_id}
        )
        |> Repo.update()

      broadcast_rollout_update(rollout)
      {:ok, :bundle_revoked}
    else
      # Transition step to running
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("running")
        |> Repo.update()

      # Assign bundle to step's nodes
      {:ok, _count} = Bundles.assign_bundle_to_nodes(bundle, step.node_ids)

      # Update NodeBundleStatus records to staging
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(nbs in NodeBundleStatus,
        where: nbs.rollout_id == ^rollout.id and nbs.node_id in ^step.node_ids
      )
      |> Repo.update_all(set: [state: "staging", last_report_at: now])

      broadcast_rollout_update(rollout)
      {:ok, :step_started}
    end
  end

  defp check_step_running(rollout, step) do
    total = length(step.node_ids)

    # Check if all nodes in this step have active_bundle_id == bundle_id
    activated_count =
      from(n in Nodes.Node,
        where: n.id in ^step.node_ids and n.active_bundle_id == ^rollout.bundle_id
      )
      |> Repo.aggregate(:count)

    # Check max_unavailable: count nodes that are offline or have failed
    unavailable_count = count_unavailable_nodes(step.node_ids)

    # With max_unavailable, the step can progress when all available nodes
    # have activated, tolerating up to max_unavailable offline nodes.
    required =
      if rollout.max_unavailable > 0 do
        max(total - rollout.max_unavailable, 0)
      else
        total
      end

    cond do
      rollout.max_unavailable > 0 and unavailable_count > rollout.max_unavailable ->
        # Too many unavailable nodes — pause the rollout
        {:ok, _} =
          rollout
          |> Rollout.state_changeset("paused",
            error: %{
              "reason" => "max_unavailable_exceeded",
              "unavailable" => unavailable_count,
              "max_unavailable" => rollout.max_unavailable
            }
          )
          |> Repo.update()

        broadcast_rollout_update(rollout)
        {:ok, :max_unavailable_exceeded}

      activated_count >= required and activated_count > 0 ->
        # Enough nodes activated — transition to verifying
        {:ok, _step} =
          step
          |> RolloutStep.state_changeset("verifying")
          |> Repo.update()

        # Update node bundle statuses
        from(nbs in NodeBundleStatus,
          where: nbs.rollout_id == ^rollout.id and nbs.node_id in ^step.node_ids
        )
        |> Repo.update_all(
          set: [
            state: "activating",
            last_report_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        )

        broadcast_rollout_update(rollout)
        {:ok, :step_verifying}

      true ->
        # Check deadline
        check_step_deadline(rollout, step)
    end
  end

  defp check_step_verifying(rollout, step) do
    # Check health gates (only for available nodes when max_unavailable is set)
    if check_health_gates(rollout, step, available_node_ids(rollout, step)) do
      # Step completed
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("completed")
        |> Repo.update()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(nbs in NodeBundleStatus,
        where: nbs.rollout_id == ^rollout.id and nbs.node_id in ^step.node_ids
      )
      |> Repo.update_all(
        set: [state: "active", activated_at: now, verified_at: now, last_report_at: now]
      )

      broadcast_rollout_update(rollout)
      {:ok, :step_completed}
    else
      check_step_deadline(rollout, step)
    end
  end

  defp check_health_gates(rollout, _step, check_node_ids) do
    gates = rollout.health_gates || %{}

    # All enabled gates must pass for available nodes
    check_heartbeat_gate(gates, check_node_ids) and
      check_error_rate_gate(gates, check_node_ids) and
      check_latency_gate(gates, check_node_ids) and
      check_cpu_gate(gates, check_node_ids) and
      check_memory_gate(gates, check_node_ids)
  end

  defp check_heartbeat_gate(gates, node_ids) do
    if Map.get(gates, "heartbeat_healthy", false) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        latest != nil && get_in(latest.health, ["status"]) == "healthy"
      end)
    else
      true
    end
  end

  defp check_error_rate_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_error_rate")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        error_rate = get_in(latest || %{}, [Access.key(:metrics, %{}), "error_rate"]) || 0.0
        error_rate <= threshold
      end)
    else
      true
    end
  end

  defp check_latency_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_latency_ms")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        latency = get_in(latest || %{}, [Access.key(:metrics, %{}), "latency_p99_ms"]) || 0.0
        latency <= threshold
      end)
    else
      true
    end
  end

  defp check_cpu_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_cpu_percent")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        cpu = get_in(latest || %{}, [Access.key(:metrics, %{}), "cpu_percent"]) || 0.0
        cpu <= threshold
      end)
    else
      true
    end
  end

  defp check_memory_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_memory_percent")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        mem = get_in(latest || %{}, [Access.key(:metrics, %{}), "memory_percent"]) || 0.0
        mem <= threshold
      end)
    else
      true
    end
  end

  defp latest_heartbeat(node_id) do
    from(h in Nodes.NodeHeartbeat,
      where: h.node_id == ^node_id,
      order_by: [desc: h.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp check_step_deadline(rollout, step) do
    deadline = rollout.progress_deadline_seconds
    elapsed = DateTime.diff(DateTime.utc_now(), step.started_at, :second)

    if elapsed > deadline do
      # Step failed — deadline exceeded
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("failed",
          error: %{"reason" => "deadline_exceeded", "elapsed_seconds" => elapsed}
        )
        |> Repo.update()

      # Fail the rollout
      {:ok, _rollout} =
        rollout
        |> Rollout.state_changeset("failed",
          error: %{
            "reason" => "step_deadline_exceeded",
            "step_index" => step.step_index,
            "elapsed_seconds" => elapsed
          }
        )
        |> Repo.update()

      broadcast_rollout_update(rollout)
      {:ok, :deadline_exceeded}
    else
      {:ok, :waiting}
    end
  end

  defp complete_rollout(rollout) do
    {:ok, updated} =
      rollout
      |> Rollout.state_changeset("completed")
      |> Repo.update()

    broadcast_rollout_update(rollout)
    {:ok, updated}
  end

  ## Private — Helpers

  defp validate_bundle_compiled(changeset) do
    bundle_id = Ecto.Changeset.get_field(changeset, :bundle_id)

    if bundle_id do
      case Bundles.get_bundle(bundle_id) do
        %{status: "compiled"} -> {:ok, changeset}
        %{} -> {:error, :bundle_not_compiled}
        nil -> {:error, :bundle_not_found}
      end
    else
      {:ok, changeset}
    end
  end

  defp chunk_into_batches(node_ids, "all_at_once", _batch_size) do
    [node_ids]
  end

  defp chunk_into_batches(node_ids, _strategy, batch_size) do
    Enum.chunk_every(node_ids, batch_size)
  end

  defp count_unavailable_nodes(node_ids) do
    from(n in Nodes.Node,
      where: n.id in ^node_ids and n.status in ~w(offline unknown)
    )
    |> Repo.aggregate(:count)
  end

  defp available_node_ids(rollout, step) do
    if rollout.max_unavailable > 0 do
      unavailable =
        from(n in Nodes.Node,
          where: n.id in ^step.node_ids and n.status in ~w(offline unknown),
          select: n.id
        )
        |> Repo.all()
        |> MapSet.new()

      Enum.reject(step.node_ids, &MapSet.member?(unavailable, &1))
    else
      step.node_ids
    end
  end

  defp get_rollout_node_ids(rollout_id) do
    from(nbs in NodeBundleStatus,
      where: nbs.rollout_id == ^rollout_id,
      select: nbs.node_id
    )
    |> Repo.all()
  end

  defp enqueue_tick(rollout_id) do
    # Skip in Oban inline/testing mode to prevent immediate execution
    # during tests — tests call tick_rollout directly
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{rollout_id: rollout_id}
      |> TickWorker.new(schedule_in: 1)
      |> Oban.insert()
    end
  end

  defp broadcast_rollout_update(rollout) do
    Phoenix.PubSub.broadcast(
      SentinelCp.PubSub,
      "rollout:#{rollout.id}",
      {:rollout_updated, rollout.id}
    )

    Phoenix.PubSub.broadcast(
      SentinelCp.PubSub,
      "rollouts:#{rollout.project_id}",
      {:rollout_updated, rollout.id}
    )
  end
end
