import Config

# Configure your database (SQLite for tests)
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sentinel_cp, SentinelCp.Repo,
  database: Path.expand("../sentinel_cp_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sentinel_cp, SentinelCpWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mweJf2rSnJcf9V7CCs4PuqhL5GB97+9ODEFraHiqbGuEA2AOh1jd0PWGlMIhr6Kv",
  server: false

# In test we don't send emails
config :sentinel_cp, SentinelCp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable Oban queues during tests (use Oban.Testing)
config :sentinel_cp, Oban, testing: :inline

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Bundle signing disabled in test (individual tests can override)
config :sentinel_cp, :bundle_signing, enabled: false

# GitHub webhook test secret
config :sentinel_cp, :github_webhook, secret: "test_webhook_secret"

# Use mock GitHub client in tests
config :sentinel_cp, :github_client, SentinelCp.Webhooks.GitHubClient.Mock
