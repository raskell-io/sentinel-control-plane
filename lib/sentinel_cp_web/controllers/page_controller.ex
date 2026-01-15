defmodule SentinelCpWeb.PageController do
  use SentinelCpWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
