defmodule SentinelCp.Services.KdlGeneratorTest do
  use SentinelCp.DataCase

  alias SentinelCp.Services.{KdlGenerator, ProjectConfig, Service}

  import SentinelCp.ProjectsFixtures
  import SentinelCp.ServicesFixtures

  defp default_config do
    %ProjectConfig{
      log_level: "info",
      metrics_port: 9090,
      custom_settings: %{}
    }
  end

  describe "build_kdl/2" do
    test "generates settings block" do
      config = %ProjectConfig{
        log_level: "debug",
        metrics_port: 9191,
        custom_settings: %{}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://localhost:3000",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      assert kdl =~ ~s(log_level "debug")
      assert kdl =~ "metrics_port 9191"
    end

    test "generates route with upstream" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          timeout_seconds: 30,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ ~s(route "/api/*")
      assert kdl =~ ~s(upstream "http://api:8080")
      assert kdl =~ "timeout 30s"
    end

    test "generates route with static response" do
      services = [
        %Service{
          name: "Health",
          slug: "health",
          route_path: "/health",
          upstream_url: nil,
          respond_status: 200,
          respond_body: "OK",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ ~s(route "/health")
      assert kdl =~ ~s(respond 200 "OK")
    end

    test "generates retry block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{"attempts" => 3, "backoff" => "exponential"},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "retry {"
      assert kdl =~ "attempts 3"
      assert kdl =~ ~s(backoff "exponential")
    end

    test "generates cache block" do
      services = [
        %Service{
          name: "Static",
          slug: "static",
          route_path: "/static/*",
          upstream_url: "http://cdn:80",
          cache: %{"ttl" => 3600, "vary" => "Accept-Encoding"},
          retry: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "cache {"
      assert kdl =~ "ttl 3600"
      assert kdl =~ ~s(vary "Accept-Encoding")
    end

    test "generates rate_limits block for services with rate limits" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          rate_limit: %{"requests" => 100, "window" => "60s", "by" => "client_ip"},
          retry: %{},
          cache: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "rate_limits {"
      assert kdl =~ ~s(limit "api")
      assert kdl =~ "requests 100"
      assert kdl =~ ~s(window "60s")
      assert kdl =~ ~s(by "client_ip")
    end

    test "does not generate rate_limits block when no services have rate limits" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          rate_limit: %{},
          retry: %{},
          cache: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      refute kdl =~ "rate_limits {"
    end

    test "generates multiple routes ordered by position" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        },
        %Service{
          name: "Health",
          slug: "health",
          route_path: "/health",
          upstream_url: nil,
          respond_status: 200,
          respond_body: "OK",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      api_pos = :binary.match(kdl, "/api/*") |> elem(0)
      health_pos = :binary.match(kdl, "/health") |> elem(0)
      assert api_pos < health_pos
    end

    test "includes custom settings" do
      config = %ProjectConfig{
        log_level: "info",
        metrics_port: 9090,
        custom_settings: %{"max_connections" => 1000}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      assert kdl =~ "max_connections 1000"
    end
  end

  describe "generate/1" do
    test "returns error when no services exist" do
      project = project_fixture()
      assert {:error, :no_services} = KdlGenerator.generate(project.id)
    end

    test "returns error when all services are disabled" do
      project = project_fixture()
      _s = service_fixture(%{project: project, enabled: false})
      assert {:error, :no_services} = KdlGenerator.generate(project.id)
    end

    test "generates KDL from database services" do
      project = project_fixture()
      _s = service_fixture(%{project: project, name: "API Backend", route_path: "/api/*"})

      assert {:ok, kdl} = KdlGenerator.generate(project.id)
      assert kdl =~ "settings {"
      assert kdl =~ "routes {"
      assert kdl =~ ~s(route "/api/*")
    end
  end
end
