defmodule SentinelCpWeb.Plugs.NodeAuth do
  @moduledoc """
  Plug for authenticating Sentinel nodes via node key.

  Nodes authenticate using the X-Sentinel-Node-Key header.
  """
  import Plug.Conn
  alias SentinelCp.Nodes

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, node_key} <- get_node_key(conn),
         {:ok, node} <- Nodes.authenticate_node(node_key) do
      conn
      |> assign(:current_node, node)
    else
      {:error, :missing_key} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Missing X-Sentinel-Node-Key header"}))
        |> halt()

      {:error, :invalid_key} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Invalid node key"}))
        |> halt()
    end
  end

  defp get_node_key(conn) do
    case get_req_header(conn, "x-sentinel-node-key") do
      [key | _] -> {:ok, key}
      [] -> {:error, :missing_key}
    end
  end
end
