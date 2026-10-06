defmodule Amauta.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  # Tabla de trabajos de Oban en el schema global (ERS 4.11).
  def up, do: Oban.Migration.up(version: 14, prefix: "global")
  def down, do: Oban.Migration.down(version: 1, prefix: "global")
end
