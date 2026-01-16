defmodule SentinelCpWeb.Router do
  use SentinelCpWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelCpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :node_auth do
    plug SentinelCpWeb.Plugs.NodeAuth
  end

  # Browser routes
  scope "/", SentinelCpWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/projects", ProjectsLive.Index, :index
    live "/projects/:project_slug/nodes", NodesLive.Index, :index
    live "/projects/:project_slug/nodes/:id", NodesLive.Show, :show
  end

  # Node-facing API (called by Sentinel nodes)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through :api

    # Node registration (no auth required - returns node key)
    post "/projects/:project_slug/nodes/register", NodeController, :register
  end

  # Node-authenticated endpoints
  scope "/api/v1/nodes", SentinelCpWeb.Api do
    pipe_through [:api, :node_auth]

    post "/:node_id/heartbeat", NodeController, :heartbeat
    get "/:node_id/bundles/latest", NodeController, :latest_bundle
  end

  # Control plane API (called by operators/API keys)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through :api

    # Project nodes management
    scope "/projects/:project_slug" do
      get "/nodes", ProjectNodesController, :index
      get "/nodes/stats", ProjectNodesController, :stats
      get "/nodes/:id", ProjectNodesController, :show
      delete "/nodes/:id", ProjectNodesController, :delete
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sentinel_cp, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SentinelCpWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
