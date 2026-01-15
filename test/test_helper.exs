ExUnit.start()

# For SQLite, the sandbox mode works but without async support
# Check if the pool is configured as Sandbox, otherwise skip
repo_config = Application.get_env(:sentinel_cp, SentinelCp.Repo, [])

if repo_config[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(SentinelCp.Repo, :manual)
end
