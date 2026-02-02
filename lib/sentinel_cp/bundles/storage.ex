defmodule SentinelCp.Bundles.Storage do
  @moduledoc """
  Storage adapter for bundle artifacts using S3/MinIO via ExAws.
  """

  @doc """
  Uploads data to the configured bucket.
  """
  def upload(key, data) when is_binary(data) do
    bucket()
    |> ExAws.S3.put_object(key, data, content_type: "application/gzip")
    |> ExAws.request(ex_aws_config())
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:upload_failed, reason}}
    end
  end

  @doc """
  Downloads data from the configured bucket.
  """
  def download(key) do
    bucket()
    |> ExAws.S3.get_object(key)
    |> ExAws.request(ex_aws_config())
    |> case do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, {:download_failed, reason}}
    end
  end

  @doc """
  Generates a presigned URL for downloading a bundle.
  """
  def presigned_url(key, expires_in \\ 3600) do
    config = ex_aws_config()

    ExAws.S3.presigned_url(config, :get, bucket(), key, expires_in: expires_in)
  end

  @doc """
  Deletes an object from the configured bucket.
  """
  def delete(key) do
    bucket()
    |> ExAws.S3.delete_object(key)
    |> ExAws.request(ex_aws_config())
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:delete_failed, reason}}
    end
  end

  @doc """
  Generates a storage key for a bundle.
  """
  def storage_key(project_id, bundle_id) do
    "bundles/#{project_id}/#{bundle_id}.tar.zst"
  end

  defp bucket do
    Application.get_env(:sentinel_cp, __MODULE__, [])
    |> Keyword.get(:bucket, "sentinel-bundles")
  end

  defp ex_aws_config do
    Application.get_env(:sentinel_cp, __MODULE__, [])
    |> Keyword.get(:ex_aws_config, [])
  end
end
