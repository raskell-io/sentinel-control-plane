defmodule SentinelCp.Projects.Project do
  @moduledoc """
  Project schema - the primary tenant boundary.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :settings, :map, default: %{}
    field :github_repo, :string
    field :github_branch, :string, default: "main"
    field :config_path, :string, default: "sentinel.kdl"

    belongs_to :org, SentinelCp.Orgs.Org
    has_many :nodes, SentinelCp.Nodes.Node
    has_many :api_keys, SentinelCp.Accounts.ApiKey

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a project.
  """
  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :description,
      :settings,
      :github_repo,
      :github_branch,
      :config_path,
      :org_id
    ])
    |> validate_required([:name, :org_id])
    |> validate_length(:name, min: 1, max: 100)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:org_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:org_id)
  end

  @doc """
  Changeset for updating a project.
  """
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :settings, :github_repo, :github_branch, :config_path])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.replace(~r/^-+|-+$/, "")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 50)
  end

  @doc """
  Returns whether rollout approvals are required for this project.
  Reads from the settings JSON map.
  """
  def approval_required?(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "approval_required", false)
  end

  @doc """
  Returns the number of approvals needed for rollouts in this project.
  Defaults to 1 if approval is required but count not specified.
  """
  def approvals_needed(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "approvals_needed", 1)
  end

  @doc """
  Returns the notification webhook URL for this project, if configured.
  """
  def notification_webhook(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "notification_webhook")
  end

  @doc """
  Returns whether notifications are enabled for this project.
  """
  def notifications_enabled?(%__MODULE__{} = project) do
    url = notification_webhook(project)
    url != nil and url != ""
  end

  @doc """
  Returns whether drift auto-remediation is enabled for this project.
  When enabled, a rollout is automatically triggered when drift is detected.
  """
  def drift_auto_remediation?(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "drift_auto_remediation", false)
  end
end
