defmodule SentinelCp.Nodes.DriftWorker do
  @moduledoc """
  Oban worker that detects configuration drift on nodes.

  Runs periodically and checks for nodes where active_bundle_id differs from
  expected_bundle_id. Creates drift events for newly drifted nodes and
  auto-resolves events when nodes come back in sync.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 30]

  require Logger

  import Ecto.Query
  alias SentinelCp.{Nodes, Notifications, Projects, Repo}
  alias SentinelCp.Nodes.Node

  @check_interval_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("DriftWorker: checking for configuration drift")

    # Find all online nodes with expected_bundle_id set
    drifted_nodes = find_drifted_nodes()
    resolved_nodes = find_resolved_nodes()

    # Create drift events for newly drifted nodes
    for node <- drifted_nodes do
      case Nodes.get_active_drift_event(node.id) do
        nil ->
          create_drift_event(node)

        _existing ->
          :ok
      end
    end

    # Auto-resolve drift events for nodes that came back in sync
    for node <- resolved_nodes do
      case Nodes.get_active_drift_event(node.id) do
        nil ->
          :ok

        event ->
          {:ok, _} = Nodes.resolve_drift_event(event, "auto_corrected")
          Logger.info("DriftWorker: auto-resolved drift for node #{node.name}")
      end
    end

    reschedule()
    :ok
  end

  defp find_drifted_nodes do
    from(n in Node,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
    )
    |> Repo.all()
  end

  defp find_resolved_nodes do
    from(n in Node,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id == n.expected_bundle_id
    )
    |> Repo.all()
  end

  defp create_drift_event(node) do
    attrs = %{
      node_id: node.id,
      project_id: node.project_id,
      expected_bundle_id: node.expected_bundle_id,
      actual_bundle_id: node.active_bundle_id,
      detected_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case Nodes.create_drift_event(attrs) do
      {:ok, event} ->
        Logger.warning("DriftWorker: detected drift on node #{node.name}")

        project = Projects.get_project!(node.project_id)
        Notifications.notify_drift_detected(node, event, project)

        {:ok, event}

      {:error, changeset} ->
        Logger.error("DriftWorker: failed to create drift event: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp reschedule do
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new(schedule_in: @check_interval_seconds)
      |> Oban.insert()
    end
  end

  @doc """
  Starts the drift worker if not already running.
  Called during application startup.
  """
  def ensure_started do
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new()
      |> Oban.insert()
    end
  end
end
