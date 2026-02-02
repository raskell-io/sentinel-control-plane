defmodule SentinelCp.Bundles.Compiler do
  @moduledoc """
  Compiler service for Sentinel configuration bundles.

  Validates KDL config via `sentinel validate`, assembles tar.zst archives,
  and computes checksums.
  """

  require Logger

  @doc """
  Validates a KDL configuration string.
  Returns {:ok, output} or {:error, output}.
  """
  def validate(config_source) when is_binary(config_source) do
    with {:ok, tmpfile} <- write_temp_config(config_source) do
      try do
        case System.cmd(sentinel_binary(), ["validate", "--config", tmpfile],
               stderr_to_stdout: true
             ) do
          {output, 0} -> {:ok, output}
          {output, _code} -> {:error, output}
        end
      rescue
        e in ErlangError ->
          {:error, "Failed to run sentinel binary: #{inspect(e)}"}
      after
        File.rm(tmpfile)
      end
    end
  end

  @doc """
  Assembles a bundle archive from config source.
  Returns {:ok, %{archive: binary, checksum: string, size: integer, manifest: map}}
  or {:error, reason}.
  """
  def assemble(bundle_id, config_source) when is_binary(config_source) do
    tmpdir = Path.join(System.tmp_dir!(), "sentinel-bundle-#{bundle_id}")
    File.mkdir_p!(tmpdir)

    try do
      # Write config
      config_path = Path.join(tmpdir, "sentinel.kdl")
      File.write!(config_path, config_source)

      # Create manifest
      config_checksum = checksum(config_source)

      manifest = %{
        "bundle_id" => bundle_id,
        "assembled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "files" => [
          %{
            "path" => "sentinel.kdl",
            "checksum" => config_checksum,
            "size" => byte_size(config_source)
          }
        ]
      }

      manifest_json = Jason.encode!(manifest, pretty: true)
      manifest_path = Path.join(tmpdir, "manifest.json")
      File.write!(manifest_path, manifest_json)

      # Create tar.zst archive
      archive = create_archive(tmpdir, ["sentinel.kdl", "manifest.json"])
      archive_checksum = checksum(archive)

      {:ok,
       %{
         archive: archive,
         checksum: archive_checksum,
         size: byte_size(archive),
         manifest: manifest
       }}
    rescue
      e ->
        {:error, "Assembly failed: #{Exception.message(e)}"}
    after
      File.rm_rf(tmpdir)
    end
  end

  @doc """
  Computes SHA256 checksum of data.
  """
  def checksum(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp write_temp_config(config_source) do
    tmpfile =
      Path.join(System.tmp_dir!(), "sentinel-validate-#{System.unique_integer([:positive])}.kdl")

    case File.write(tmpfile, config_source) do
      :ok -> {:ok, tmpfile}
      {:error, reason} -> {:error, "Failed to write temp config: #{inspect(reason)}"}
    end
  end

  defp create_archive(dir, files) do
    # Create a tar archive, then compress with zstd if available, otherwise gzip
    tar_data = create_tar(dir, files)

    case System.cmd("which", ["zstd"], stderr_to_stdout: true) do
      {_, 0} -> compress_zstd(tar_data)
      _ -> compress_gzip(tar_data)
    end
  end

  defp create_tar(dir, files) do
    # Use Erlang's :erl_tar for portability
    {:ok, tar_data} =
      files
      |> Enum.map(fn file ->
        path = Path.join(dir, file)
        content = File.read!(path)
        {String.to_charlist(file), content}
      end)
      |> :erl_tar.create({:binary, []})

    tar_data
  end

  defp compress_zstd(data) do
    tmpfile = Path.join(System.tmp_dir!(), "bundle-#{System.unique_integer([:positive])}.tar")
    outfile = tmpfile <> ".zst"

    try do
      File.write!(tmpfile, data)
      {_, 0} = System.cmd("zstd", ["-q", "--rm", tmpfile, "-o", outfile])
      File.read!(outfile)
    after
      File.rm(tmpfile)
      File.rm(outfile)
    end
  end

  defp compress_gzip(data) do
    :zlib.gzip(data)
  end

  defp sentinel_binary do
    Application.get_env(:sentinel_cp, __MODULE__, [])
    |> Keyword.get(:sentinel_binary, "sentinel")
  end
end
