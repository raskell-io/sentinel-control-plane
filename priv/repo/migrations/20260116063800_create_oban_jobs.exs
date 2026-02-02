defmodule SentinelCp.Repo.Migrations.CreateObanJobs do
  use Ecto.Migration

  def up do
    Oban.Migrations.SQLite.up(version: 1)
  end

  def down do
    Oban.Migrations.SQLite.down(version: 1)
  end
end
