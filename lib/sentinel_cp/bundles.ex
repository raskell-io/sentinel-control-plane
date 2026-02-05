defmodule SentinelCp.Bundles do
  @moduledoc """
  The Bundles context handles bundle lifecycle management.

  Bundles are immutable, content-addressed configuration artifacts that are
  compiled from KDL config, stored in S3/MinIO, and distributed to nodes.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Bundles.Bundle

  @doc """
  Creates a bundle and enqueues compilation.
  """
  def create_bundle(attrs) do
    changeset = Bundle.create_changeset(%Bundle{}, attrs)

    case Repo.insert(changeset) do
      {:ok, bundle} ->
        enqueue_compilation(bundle)
        {:ok, bundle}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Lists bundles for a project, ordered by most recent first.
  """
  def list_bundles(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(b in Bundle,
        where: b.project_id == ^project_id,
        order_by: [desc: b.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      Enum.reduce(opts, query, fn
        {:status, status}, q -> where(q, [b], b.status == ^status)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a bundle by ID.
  """
  def get_bundle(id), do: Repo.get(Bundle, id)

  @doc """
  Gets a bundle by ID, raises if not found.
  """
  def get_bundle!(id), do: Repo.get!(Bundle, id)

  @doc """
  Gets the latest compiled bundle for a project.
  """
  def get_latest_bundle(project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id and b.status == "compiled",
      order_by: [desc: b.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Updates a bundle's compilation results.
  """
  def update_compilation(bundle, attrs) do
    bundle
    |> Bundle.compilation_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a bundle as a specific status.
  """
  def update_status(bundle, status) do
    bundle
    |> Bundle.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Updates a bundle's SBOM data.
  """
  def update_bundle_sbom(bundle, sbom) do
    bundle
    |> Bundle.compilation_changeset(%{sbom: sbom, sbom_format: "cyclonedx+json"})
    |> Repo.update()
  end

  @doc """
  Updates a bundle's risk level and reasons.
  """
  def update_risk(bundle, risk_level, risk_reasons) do
    bundle
    |> Bundle.compilation_changeset(%{risk_level: risk_level, risk_reasons: risk_reasons})
    |> Repo.update()
  end

  @doc """
  Assigns a bundle to one or more nodes as their staged bundle.
  """
  def assign_bundle_to_nodes(bundle, node_ids) when is_list(node_ids) do
    {count, _} =
      from(n in SentinelCp.Nodes.Node,
        where: n.id in ^node_ids and n.project_id == ^bundle.project_id
      )
      |> Repo.update_all(set: [staged_bundle_id: bundle.id])

    {:ok, count}
  end

  @doc """
  Counts bundles by status for a project.
  """
  def count_bundles(project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id,
      group_by: b.status,
      select: {b.status, count(b.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Revokes a compiled bundle, preventing further distribution.

  Clears `staged_bundle_id` on any nodes that have this bundle staged.
  Only compiled bundles can be revoked.
  """
  def revoke_bundle(%Bundle{status: "compiled"} = bundle) do
    Repo.transaction(fn ->
      {:ok, revoked} = update_status(bundle, "revoked")

      # Clear staged_bundle_id on nodes that have this bundle staged
      from(n in SentinelCp.Nodes.Node,
        where: n.staged_bundle_id == ^bundle.id
      )
      |> Repo.update_all(set: [staged_bundle_id: nil])

      revoked
    end)
  end

  def revoke_bundle(%Bundle{}), do: {:error, :invalid_state}

  @doc """
  Deletes a bundle (only if pending or failed).
  """
  def delete_bundle(%Bundle{status: status} = bundle) when status in ["pending", "failed"] do
    Repo.delete(bundle)
  end

  def delete_bundle(%Bundle{}) do
    {:error, :cannot_delete_active_bundle}
  end

  # Enqueue compilation via Oban
  defp enqueue_compilation(bundle) do
    %{bundle_id: bundle.id}
    |> SentinelCp.Bundles.CompileWorker.new()
    |> Oban.insert()
  end

  ## Config Validation Rules

  alias SentinelCp.Bundles.{ConfigValidationRule, ConfigValidator}

  @doc """
  Lists all config validation rules for a project.
  """
  def list_validation_rules(project_id) do
    from(r in ConfigValidationRule,
      where: r.project_id == ^project_id,
      order_by: [asc: r.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a validation rule by ID.
  """
  def get_validation_rule(id), do: Repo.get(ConfigValidationRule, id)

  @doc """
  Gets a validation rule by ID, raises if not found.
  """
  def get_validation_rule!(id), do: Repo.get!(ConfigValidationRule, id)

  @doc """
  Creates a config validation rule.
  """
  def create_validation_rule(attrs) do
    %ConfigValidationRule{}
    |> ConfigValidationRule.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a config validation rule.
  """
  def update_validation_rule(%ConfigValidationRule{} = rule, attrs) do
    rule
    |> ConfigValidationRule.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a config validation rule.
  """
  def delete_validation_rule(%ConfigValidationRule{} = rule) do
    Repo.delete(rule)
  end

  @doc """
  Validates a bundle's config against project validation rules.

  Returns `{:ok, warnings}` if validation passes.
  Returns `{:error, errors, warnings}` if validation fails.
  """
  def validate_bundle_config(%Bundle{} = bundle) do
    rules = list_validation_rules(bundle.project_id)
    config_source = bundle.config_source || ""

    ConfigValidator.validate(config_source, rules)
  end

  @doc """
  Validates config source against project validation rules.
  """
  def validate_config(project_id, config_source) when is_binary(config_source) do
    rules = list_validation_rules(project_id)
    ConfigValidator.validate(config_source, rules)
  end
end
