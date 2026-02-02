defmodule SentinelCp.Bundles.CompileWorker do
  @moduledoc """
  Oban worker that compiles bundle configuration.

  Triggered when a new bundle is created. Validates the config,
  assembles the archive, uploads to storage, and updates the bundle record.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias SentinelCp.Bundles
  alias SentinelCp.Bundles.{Compiler, Storage}
  alias SentinelCp.Audit

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bundle_id" => bundle_id}}) do
    bundle = Bundles.get_bundle!(bundle_id)

    Logger.info("Starting compilation for bundle #{bundle_id}")

    # Mark as compiling
    {:ok, bundle} = Bundles.update_status(bundle, "compiling")

    case compile_bundle(bundle) do
      {:ok, result} ->
        {:ok, _} =
          Bundles.update_compilation(bundle, %{
            status: "compiled",
            checksum: result.checksum,
            size_bytes: result.size,
            storage_key: result.storage_key,
            manifest: result.manifest,
            compiler_output: result.compiler_output
          })

        Audit.log_system_action("bundle.compiled", "bundle", bundle.id,
          project_id: bundle.project_id,
          metadata: %{checksum: result.checksum, size: result.size}
        )

        Phoenix.PubSub.broadcast(
          SentinelCp.PubSub,
          "bundles:#{bundle.project_id}",
          {:bundle_compiled, bundle_id}
        )

        Logger.info("Bundle #{bundle_id} compiled (#{result.size} bytes)")
        :ok

      {:error, reason} ->
        compiler_output = if is_binary(reason), do: reason, else: inspect(reason)

        {:ok, _} =
          Bundles.update_compilation(bundle, %{
            status: "failed",
            compiler_output: compiler_output
          })

        Audit.log_system_action("bundle.compilation_failed", "bundle", bundle.id,
          project_id: bundle.project_id,
          metadata: %{error: compiler_output}
        )

        Phoenix.PubSub.broadcast(
          SentinelCp.PubSub,
          "bundles:#{bundle.project_id}",
          {:bundle_failed, bundle_id}
        )

        Logger.error("Bundle #{bundle_id} compilation failed: #{compiler_output}")
        :ok
    end
  end

  defp compile_bundle(bundle) do
    with {:ok, compiler_output} <- Compiler.validate(bundle.config_source),
         {:ok, assembly} <- Compiler.assemble(bundle.id, bundle.config_source),
         storage_key <- Storage.storage_key(bundle.project_id, bundle.id),
         :ok <- Storage.upload(storage_key, assembly.archive) do
      {:ok,
       %{
         checksum: assembly.checksum,
         size: assembly.size,
         storage_key: storage_key,
         manifest: assembly.manifest,
         compiler_output: compiler_output
       }}
    end
  end
end
