defmodule SentinelCpWeb.Api.BundleController do
  @moduledoc """
  API controller for bundle management.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Bundles, Projects, Audit}

  @doc """
  POST /api/v1/projects/:project_slug/bundles
  Creates a new bundle from KDL config source.
  """
  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- %{
           project_id: project.id,
           version: params["version"],
           config_source: params["config_source"],
           created_by_id: conn.assigns[:current_api_key] && conn.assigns.current_api_key.user_id,
           risk_level: params["risk_level"] || "low"
         },
         {:ok, bundle} <- Bundles.create_bundle(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "bundle.created", "bundle", bundle.id,
        project_id: project.id,
        changes: %{version: bundle.version}
      )

      conn
      |> put_status(:created)
      |> json(%{
        id: bundle.id,
        version: bundle.version,
        status: bundle.status,
        project_id: project.id
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/bundles
  Lists bundles for a project.
  """
  def index(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      opts =
        []
        |> then(fn opts ->
          if params["status"], do: [{:status, params["status"]} | opts], else: opts
        end)

      bundles = Bundles.list_bundles(project.id, opts)

      conn
      |> put_status(:ok)
      |> json(%{
        bundles: Enum.map(bundles, &bundle_to_json/1),
        total: length(bundles)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/bundles/:id
  Shows bundle details.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => bundle_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, bundle} <- get_bundle(bundle_id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{bundle: bundle_to_json(bundle)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :bundle_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Bundle not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/bundles/:id/download
  Redirects to presigned download URL.
  """
  def download(conn, %{"project_slug" => project_slug, "id" => bundle_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, bundle} <- get_bundle(bundle_id, project.id),
         true <- bundle.status == "compiled" || {:error, :not_compiled},
         {:ok, url} <- Bundles.Storage.presigned_url(bundle.storage_key) do
      conn
      |> put_status(:ok)
      |> json(%{download_url: url, checksum: bundle.checksum, size: bundle.size_bytes})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :bundle_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Bundle not found"})

      {:error, :not_compiled} ->
        conn |> put_status(:conflict) |> json(%{error: "Bundle is not yet compiled"})

      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/bundles/:id/assign
  Assigns a bundle to nodes.
  """
  def assign(conn, %{"project_slug" => project_slug, "id" => bundle_id} = params) do
    node_ids = params["node_ids"] || []

    with {:ok, project} <- get_project(project_slug),
         {:ok, bundle} <- get_bundle(bundle_id, project.id),
         true <- bundle.status == "compiled" || {:error, :not_compiled},
         {:ok, count} <- Bundles.assign_bundle_to_nodes(bundle, node_ids) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "bundle.assigned", "bundle", bundle.id,
        project_id: project.id,
        changes: %{node_ids: node_ids, count: count}
      )

      conn
      |> put_status(:ok)
      |> json(%{assigned: count})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :bundle_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Bundle not found"})

      {:error, :not_compiled} ->
        conn |> put_status(:conflict) |> json(%{error: "Bundle must be compiled before assignment"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_bundle(id, project_id) do
    case Bundles.get_bundle(id) do
      nil -> {:error, :bundle_not_found}
      %{project_id: ^project_id} = bundle -> {:ok, bundle}
      _ -> {:error, :bundle_not_found}
    end
  end

  defp bundle_to_json(bundle) do
    %{
      id: bundle.id,
      version: bundle.version,
      status: bundle.status,
      checksum: bundle.checksum,
      size_bytes: bundle.size_bytes,
      risk_level: bundle.risk_level,
      manifest: bundle.manifest,
      compiler_output: bundle.compiler_output,
      inserted_at: bundle.inserted_at,
      updated_at: bundle.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
