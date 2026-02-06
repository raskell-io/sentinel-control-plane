Mox.defmock(SentinelCp.Webhooks.GitHubClient.Mock,
  for: SentinelCp.Webhooks.GitHubClient
)

# Start Wallaby only if running E2E tests and ChromeDriver is available
# E2E tests require ChromeDriver to be installed
if System.get_env("WALLABY_DRIVER") != "disabled" do
  case System.cmd("which", ["chromedriver"], stderr_to_stdout: true) do
    {_, 0} ->
      {:ok, _} = Application.ensure_all_started(:wallaby)
    _ ->
      IO.puts("ChromeDriver not found - E2E tests will be skipped")
  end
end

# Exclude e2e and integration tests by default (run with --include e2e or --include integration)
ExUnit.start(exclude: [:e2e, :integration])

# For SQLite, the sandbox mode works but without async support
# Check if the pool is configured as Sandbox, otherwise skip
repo_config = Application.get_env(:sentinel_cp, SentinelCp.Repo, [])

if repo_config[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(SentinelCp.Repo, :manual)
end
