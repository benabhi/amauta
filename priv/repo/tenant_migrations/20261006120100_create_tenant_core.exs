defmodule Amauta.Repo.TenantMigrations.CreateTenantCore do
  use Ecto.Migration

  # Tablas de cada institución. El prefijo lo aplica el migrador
  # (Amauta.Tenancy.migrate/1), nunca se escribe acá.
  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :email, :string, null: false
      add :api_token_hash, :binary

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:api_token_hash])

    create table(:courses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:courses, [:slug])

    create table(:role_assignments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, null: false
      # Ámbito: nulo = toda la institución; si no, el curso.
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:role_assignments, [:user_id])

    create table(:posts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:posts, [:course_id, :inserted_at])

    create table(:audit_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, :uuid
      add :action, :string, null: false
      add :subject_type, :string
      add :subject_id, :uuid
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_events, [:subject_type, :subject_id])
  end
end
