defmodule SentinelCp.Rollouts.TickWorker do
  @moduledoc """
  Oban worker that drives rollout progression.

  Self-scheduling: each tick reschedules itself in 5 seconds if the rollout
  is still running. Uses unique constraint to prevent duplicate ticks.
  """
  use Oban.Worker,
    queue: :rollouts,
    max_attempts: 3,
    unique: [keys: [:rollout_id], period: 10]

  require Logger

  alias SentinelCp.Rollouts

  @tick_interval_seconds 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rollout_id" => rollout_id}}) do
    case Rollouts.get_rollout(rollout_id) do
      nil ->
        Logger.warning("TickWorker: rollout #{rollout_id} not found, stopping")
        :ok

      %{state: "running"} = rollout ->
        Logger.debug("TickWorker: ticking rollout #{rollout_id}")

        case Rollouts.tick_rollout(rollout) do
          {:ok, :step_started} ->
            reschedule(rollout_id)
            :ok

          {:ok, :step_verifying} ->
            reschedule(rollout_id)
            :ok

          {:ok, :step_completed} ->
            reschedule(rollout_id)
            :ok

          {:ok, :waiting} ->
            reschedule(rollout_id)
            :ok

          {:ok, %Rollouts.Rollout{state: "completed"}} ->
            Logger.info("TickWorker: rollout #{rollout_id} completed")
            :ok

          {:ok, :deadline_exceeded} ->
            Logger.warning("TickWorker: rollout #{rollout_id} failed (deadline exceeded)")
            :ok

          {:ok, :not_running} ->
            Logger.info("TickWorker: rollout #{rollout_id} is no longer running")
            :ok
        end

      %{state: state} ->
        Logger.info("TickWorker: rollout #{rollout_id} in state #{state}, stopping ticks")
        :ok
    end
  end

  defp reschedule(rollout_id) do
    # Skip rescheduling in Oban inline/testing mode to prevent infinite recursion
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{rollout_id: rollout_id}
      |> __MODULE__.new(schedule_in: @tick_interval_seconds)
      |> Oban.insert()
    end
  end
end
