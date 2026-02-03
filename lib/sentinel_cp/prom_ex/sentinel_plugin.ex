defmodule SentinelCp.PromEx.SentinelPlugin do
  @moduledoc """
  Custom PromEx plugin for Sentinel Control Plane metrics.

  Emits:
  - `sentinel_cp_bundles_total` — counter by status (compiled, failed)
  - `sentinel_cp_nodes_total` — gauge by status (online, offline)
  - `sentinel_cp_rollouts_active` — gauge of running rollouts
  - `sentinel_cp_webhook_events_total` — counter by event type
  """
  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      :sentinel_cp_polling_metrics,
      poll_rate,
      {__MODULE__, :poll_metrics, []},
      [
        last_value(
          [:sentinel_cp, :nodes, :total],
          event_name: [:sentinel_cp, :nodes, :count],
          description: "Total number of nodes by status",
          measurement: :count,
          tags: [:status]
        ),
        last_value(
          [:sentinel_cp, :rollouts, :active],
          event_name: [:sentinel_cp, :rollouts, :active_count],
          description: "Number of currently active rollouts",
          measurement: :count
        )
      ]
    )
  end

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :sentinel_cp_event_metrics,
      [
        counter(
          [:sentinel_cp, :bundles, :total],
          event_name: [:sentinel_cp, :bundles, :created],
          description: "Total bundles created by status",
          measurement: :count,
          tags: [:status]
        ),
        counter(
          [:sentinel_cp, :webhook, :events, :total],
          event_name: [:sentinel_cp, :webhook, :received],
          description: "Total webhook events received by type",
          measurement: :count,
          tags: [:event_type]
        )
      ]
    )
  end

  @doc false
  def poll_metrics do
    # Node counts by status
    for status <- ["online", "offline", "unknown"] do
      count = poll_node_count(status)

      :telemetry.execute(
        [:sentinel_cp, :nodes, :count],
        %{count: count},
        %{status: status}
      )
    end

    # Active rollouts
    active_rollouts = poll_active_rollouts()

    :telemetry.execute(
      [:sentinel_cp, :rollouts, :active_count],
      %{count: active_rollouts},
      %{}
    )
  end

  defp poll_node_count(status) do
    import Ecto.Query

    SentinelCp.Repo.aggregate(
      from(n in "nodes", where: n.status == ^status),
      :count
    )
  rescue
    _ -> 0
  end

  defp poll_active_rollouts do
    import Ecto.Query

    SentinelCp.Repo.aggregate(
      from(r in "rollouts", where: r.state in ["pending", "in_progress"]),
      :count
    )
  rescue
    _ -> 0
  end
end
