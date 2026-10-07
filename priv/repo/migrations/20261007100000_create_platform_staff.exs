defmodule Amauta.Repo.Migrations.CreatePlatformStaff do
  use Ecto.Migration

  # Personal de la instancia (ERS 4.6 y RF-ROL-009): vive en el schema global
  # y no es persona de ninguna institución. Su actividad queda en una
  # auditoría de plataforma inmutable.
  def change do
    create table(:platform_staff, prefix: "global", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :role, :string, null: false, default: "superadmin"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_staff, [:email], prefix: "global")

    create constraint(:platform_staff, :role_must_be_valid,
             check: "role IN ('superadmin')",
             prefix: "global"
           )

    create table(:platform_staff_tokens, prefix: "global", primary_key: false) do
      add :id, :uuid, primary_key: true

      add :staff_id,
          references(:platform_staff, type: :uuid, on_delete: :delete_all, prefix: "global"),
          null: false

      add :token, :binary, null: false
      add :context, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:platform_staff_tokens, [:context, :token], prefix: "global")

    create table(:platform_audit_events, prefix: "global", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :staff_id, :uuid
      add :action, :string, null: false
      add :subject_type, :string
      add :subject_id, :uuid
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:platform_audit_events, [:inserted_at], prefix: "global")

    execute(
      """
      CREATE FUNCTION global.forbid_mutation() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'audit events are immutable' USING ERRCODE = 'restrict_violation';
      END;
      $$
      """,
      "DROP FUNCTION global.forbid_mutation()"
    )

    execute(
      """
      CREATE TRIGGER platform_audit_events_immutable
      BEFORE UPDATE OR DELETE ON global.platform_audit_events
      FOR EACH ROW EXECUTE FUNCTION global.forbid_mutation()
      """,
      "DROP TRIGGER platform_audit_events_immutable ON global.platform_audit_events"
    )
  end
end
