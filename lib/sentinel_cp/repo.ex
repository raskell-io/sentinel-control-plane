defmodule SentinelCp.Repo do
  use Ecto.Repo,
    otp_app: :sentinel_cp,
    adapter: Application.compile_env(:sentinel_cp, :ecto_adapter, Ecto.Adapters.SQLite3)
end
