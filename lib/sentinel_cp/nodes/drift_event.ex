defmodule SentinelCp.Nodes.DriftEvent do
  @moduledoc """
  Schema for drift events.

  A drift event is created when a node's active_bundle_id differs from its
  expected_bundle_id. The expected bundle is set when a rollout step completes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @resolutions ~w(auto_corrected manual rollout_started)

  schema "drift_events" do
    field :expected_bundle_id, :binary_id
    field :actual_bundle_id, :binary_id
    field :detected_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :resolution, :string

    belongs_to :node, SentinelCp.Nodes.Node
    belongs_to :project, SentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new drift event.
  """
  def create_changeset(drift_event, attrs) do
    drift_event
    |> cast(attrs, [:node_id, :project_id, :expected_bundle_id, :actual_bundle_id, :detected_at])
    |> validate_required([:node_id, :project_id, :expected_bundle_id, :detected_at])
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for resolving a drift event.
  """
  def resolve_changeset(drift_event, resolution) do
    drift_event
    |> change(%{
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      resolution: resolution
    })
    |> validate_inclusion(:resolution, @resolutions)
  end
end
