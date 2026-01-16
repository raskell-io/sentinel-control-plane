defmodule SentinelCpWeb.PageController do
  use SentinelCpWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/projects")
  end
end
