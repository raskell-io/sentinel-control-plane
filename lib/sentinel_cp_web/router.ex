defmodule SentinelCpWeb.Router do
  use SentinelCpWeb, :router

  import SentinelCpWeb.Plugs.Auth,
    only: [fetch_current_user: 2, require_authenticated_user: 2, redirect_if_user_is_authenticated: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelCpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :node_auth do
    plug SentinelCpWeb.Plugs.NodeAuth
  end

  pipeline :api_auth do
    plug SentinelCpWeb.Plugs.ApiAuth
  end

  # Auth routes (no login required)
  scope "/", SentinelCpWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live "/login", AuthLive.Login, :login
  end

  # Session management
  scope "/", SentinelCpWeb do
    pipe_through [:browser]

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  # Browser routes (login required)
  scope "/", SentinelCpWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :home

    live "/projects", ProjectsLive.Index, :index
    live "/projects/:project_slug/nodes", NodesLive.Index, :index
    live "/projects/:project_slug/nodes/:id", NodesLive.Show, :show
    live "/projects/:project_slug/bundles", BundlesLive.Index, :index
    live "/projects/:project_slug/bundles/:id", BundlesLive.Show, :show
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
    pipe_through [:api, :api_auth]

    # Project nodes management
    scope "/projects/:project_slug" do
      get "/nodes", ProjectNodesController, :index
      get "/nodes/stats", ProjectNodesController, :stats
      get "/nodes/:id", ProjectNodesController, :show
      delete "/nodes/:id", ProjectNodesController, :delete

      # Bundle management
      post "/bundles", BundleController, :create
      get "/bundles", BundleController, :index
      get "/bundles/:id", BundleController, :show
      get "/bundles/:id/download", BundleController, :download
      post "/bundles/:id/assign", BundleController, :assign
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
