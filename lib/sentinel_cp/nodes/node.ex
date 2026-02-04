defmodule SentinelCp.Nodes.Node do
  @moduledoc """
  Node schema representing a Sentinel proxy instance.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(online offline unknown)
  @node_key_length 32

  schema "nodes" do
    field :name, :string
    field :node_key, :string, virtual: true, redact: true
    field :node_key_hash, :string, redact: true
    field :labels, :map, default: %{}
    field :capabilities, {:array, :string}, default: []
    field :version, :string
    field :ip, :string
    field :hostname, :string
    field :metadata, :map, default: %{}
    field :status, :string, default: "unknown"
    field :last_seen_at, :utc_datetime
    field :registered_at, :utc_datetime
    field :active_bundle_id, :binary_id
    field :staged_bundle_id, :binary_id
    field :token_issued_at, :utc_datetime
    field :token_expires_at, :utc_datetime
    field :auth_method, :string, default: "static_key"

    belongs_to :project, SentinelCp.Projects.Project
    has_many :heartbeats, SentinelCp.Nodes.NodeHeartbeat
    has_many :events, SentinelCp.Nodes.NodeEvent
    has_one :runtime_config, SentinelCp.Nodes.NodeRuntimeConfig

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for registering a new node.
  Generates a node key that should be returned to the node once.
  """
  def registration_changeset(node, attrs) do
    node_key = generate_node_key()

    node
    |> cast(attrs, [
      :name,
      :labels,
      :capabilities,
      :version,
      :ip,
      :hostname,
      :metadata,
      :project_id
    ])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/,
      message:
        "must start with alphanumeric and contain only alphanumeric, underscore, dot, or hyphen"
    )
    |> put_change(:node_key, node_key)
    |> put_change(:node_key_hash, hash_node_key(node_key))
    |> put_change(:status, "online")
    |> put_change(:registered_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:last_seen_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating node metadata on heartbeat.
  """
  def heartbeat_changeset(node, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    node
    |> cast(attrs, [:version, :ip, :hostname, :metadata, :capabilities])
    |> put_change(:status, "online")
    |> put_change(:last_seen_at, now)
  end

  @doc """
  Changeset for marking a node offline.
  """
  def offline_changeset(node) do
    node
    |> change(status: "offline")
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for updating node labels.
  """
  def labels_changeset(node, labels) do
    change(node, labels: labels)
  end

  @doc """
  Verifies a node key against its hash.
  """
  def valid_node_key?(%__MODULE__{node_key_hash: hash}, node_key) do
    hash_node_key(node_key) == hash
  end

  def valid_node_key?(_, _), do: false

  @doc """
  Checks if a node is considered online based on last_seen_at.
  Default threshold is 2 minutes.
  """
  def online?(%__MODULE__{last_seen_at: nil}), do: false

  def online?(%__MODULE__{last_seen_at: last_seen_at}, threshold_seconds \\ 120) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, last_seen_at, :second)
    diff <= threshold_seconds
  end

  @doc """
  Generates a secure random node key.
  """
  def generate_node_key do
    :crypto.strong_rand_bytes(@node_key_length)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Hashes a node key for storage.
  """
  def hash_node_key(key) do
    :crypto.hash(:sha256, key)
    |> Base.encode64()
  end
end
