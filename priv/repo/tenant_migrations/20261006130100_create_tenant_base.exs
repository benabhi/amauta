defmodule Amauta.Repo.TenantMigrations.CreateTenantBase do
  use Ecto.Migration

  # Primera migración de cada institución. El prefijo lo aplica
  # Amauta.Tenancy.Migrator; nunca se escribe acá.
  #
  # Las tablas de dominio (personas, roles, cursos…) llegan con sus propias
  # migraciones. Esta deja la base común: la auditoría inmutable.
  def change do
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
    create index(:audit_events, [:inserted_at])

    # Inmutable en la base: se rechaza cualquier UPDATE o DELETE. La función
    # vive en el schema de la institución para que su respaldo sea autónomo.
    execute(
      """
      CREATE FUNCTION #{prefix()}.forbid_mutation() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'audit events are immutable' USING ERRCODE = 'restrict_violation';
      END;
      $$
      """,
      "DROP FUNCTION #{prefix()}.forbid_mutation()"
    )

    execute(
      """
      CREATE TRIGGER audit_events_immutable
      BEFORE UPDATE OR DELETE ON #{prefix()}.audit_events
      FOR EACH ROW EXECUTE FUNCTION #{prefix()}.forbid_mutation()
      """,
      "DROP TRIGGER audit_events_immutable ON #{prefix()}.audit_events"
    )
  end
end
