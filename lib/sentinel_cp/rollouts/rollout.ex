defmodule SentinelCp.Rollouts.Rollout do
  @moduledoc """
  Rollout schema representing a batched bundle deployment to nodes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states ~w(pending running paused completed cancelled failed)
  @strategies ~w(rolling all_at_once)

  schema "rollouts" do
    field :target_selector, :map
    field :strategy, :string, default: "rolling"
    field :batch_size, :integer, default: 1
    field :max_unavailable, :integer, default: 0
    field :progress_deadline_seconds, :integer, default: 600
    field :health_gates, :map, default: %{"heartbeat_healthy" => true}
    field :state, :string, default: "pending"
    field :created_by_id, :binary_id
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error, :map

    belongs_to :project, SentinelCp.Projects.Project
    belongs_to :bundle, SentinelCp.Bundles.Bundle
    has_many :steps, SentinelCp.Rollouts.RolloutStep
    has_many :node_bundle_statuses, SentinelCp.Rollouts.NodeBundleStatus

    timestamps(type: :utc_datetime)
  end

  def create_changeset(rollout, attrs) do
    rollout
    |> cast(attrs, [
      :project_id,
      :bundle_id,
      :target_selector,
      :strategy,
      :batch_size,
      :max_unavailable,
      :progress_deadline_seconds,
      :health_gates,
      :created_by_id
    ])
    |> validate_required([:project_id, :bundle_id, :target_selector])
    |> validate_inclusion(:strategy, @strategies)
    |> validate_number(:batch_size, greater_than: 0)
    |> validate_number(:max_unavailable, greater_than_or_equal_to: 0)
    |> validate_number(:progress_deadline_seconds, greater_than: 0)
    |> validate_target_selector()
    |> put_change(:state, "pending")
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:bundle_id)
  end

  def state_changeset(rollout, state, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      %{state: state}
      |> maybe_set_started_at(state, rollout, now)
      |> maybe_set_completed_at(state, now)
      |> maybe_set_error(opts[:error])

    rollout
    |> change(changes)
    |> validate_inclusion(:state, @states)
  end

  defp maybe_set_started_at(changes, "running", %{started_at: nil}, now) do
    Map.put(changes, :started_at, now)
  end

  defp maybe_set_started_at(changes, _state, _rollout, _now), do: changes

  defp maybe_set_completed_at(changes, state, now) when state in ~w(completed cancelled failed) do
    Map.put(changes, :completed_at, now)
  end

  defp maybe_set_completed_at(changes, _state, _now), do: changes

  defp maybe_set_error(changes, nil), do: changes
  defp maybe_set_error(changes, error), do: Map.put(changes, :error, error)

  defp validate_target_selector(changeset) do
    validate_change(changeset, :target_selector, fn :target_selector, selector ->
      case selector do
        %{"type" => "all"} ->
          []

        %{"type" => "labels", "labels" => labels} when is_map(labels) and map_size(labels) > 0 ->
          []

        %{"type" => "node_ids", "node_ids" => ids} when is_list(ids) and length(ids) > 0 ->
          []

        _ ->
          [
            target_selector:
              "must be {type: all}, {type: labels, labels: {...}}, or {type: node_ids, node_ids: [...]}"
          ]
      end
    end)
  end
end
