defmodule SentinelCp.Services.BundleIntegration do
  @moduledoc """
  Integrates structured services with the bundle compilation pipeline.

  Generates KDL from services and creates bundles for compilation.
  """

  alias SentinelCp.Bundles
  alias SentinelCp.Services.KdlGenerator

  @doc """
  Creates a bundle from the project's service definitions.

  Generates KDL configuration from enabled services, then creates a bundle
  and enqueues compilation.

  Returns `{:ok, bundle}` or `{:error, reason}`.
  """
  def create_bundle_from_services(project_id, version, opts \\ []) do
    case KdlGenerator.generate(project_id) do
      {:ok, kdl} ->
        attrs = %{
          project_id: project_id,
          version: version,
          config_source: kdl
        }

        attrs =
          if created_by_id = Keyword.get(opts, :created_by_id) do
            Map.put(attrs, :created_by_id, created_by_id)
          else
            attrs
          end

        Bundles.create_bundle(attrs)

      {:error, :no_services} ->
        {:error, :no_services}
    end
  end

  @doc """
  Generates a KDL preview without creating a bundle.

  Returns `{:ok, kdl_string}` or `{:error, :no_services}`.
  """
  def preview_kdl(project_id) do
    KdlGenerator.generate(project_id)
  end
end
