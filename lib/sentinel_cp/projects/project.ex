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

    has_many :nodes, SentinelCp.Nodes.Node
    has_many :api_keys, SentinelCp.Accounts.ApiKey

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a project.
  """
  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for updating a project.
  """
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :settings])
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
end
