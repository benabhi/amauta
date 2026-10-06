defmodule Amauta.Repo.Migrations.CreateGlobalInstitutions do
  use Ecto.Migration

  # Schema global: registro de instituciones (ERS 4.11) con el estado de las
  # migraciones de cada una (RF-ADM-006).
  def change do
    execute "CREATE SCHEMA IF NOT EXISTS global", "DROP SCHEMA IF EXISTS global CASCADE"

    create table(:institutions, prefix: "global", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :short_name, :string
      add :schema_name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :timezone, :string, null: false, default: "America/Argentina/Buenos_Aires"
      add :locale, :string, null: false, default: "es"
      # Última migración aplicada al schema y error del último intento.
      add :schema_version, :bigint
      add :migration_error, :text
      add :migrated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:institutions, [:slug], prefix: "global")
    create unique_index(:institutions, [:schema_name], prefix: "global")

    create constraint(:institutions, :status_must_be_valid,
             check: "status IN ('active', 'suspended')",
             prefix: "global"
           )
  end
end
