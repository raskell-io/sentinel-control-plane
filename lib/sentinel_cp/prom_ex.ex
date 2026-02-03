defmodule SentinelCp.PromEx do
  @moduledoc """
  PromEx configuration for Prometheus metrics.

  Provides out-of-the-box metrics for Phoenix, Ecto, Oban, and BEAM,
  plus custom Sentinel-specific application metrics.
  """
  use PromEx, otp_app: :sentinel_cp

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: SentinelCpWeb.Router, endpoint: SentinelCpWeb.Endpoint},
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,
      SentinelCp.PromEx.SentinelPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "sentinel-cp",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
