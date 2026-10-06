defmodule Amauta.Repo.Migrations.CreateGlobalInstitutions do
  use Ecto.Migration

  # Schema global: registro de instituciones (ERS 4.11).
  def change do
    execute "CREATE SCHEMA IF NOT EXISTS global", "DROP SCHEMA IF EXISTS global CASCADE"

    create table(:institutions, prefix: "global", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :schema_name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:institutions, [:slug], prefix: "global")
    create unique_index(:institutions, [:schema_name], prefix: "global")
  end
end
