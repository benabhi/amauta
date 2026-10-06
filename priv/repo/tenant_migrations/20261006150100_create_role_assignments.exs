defmodule Amauta.Repo.TenantMigrations.CreateRoleAssignments do
  use Ecto.Migration

  # Asignación de rol = persona + rol + ámbito (RF-ROL-003). Sin ámbito
  # concreto (scope_id nulo) es toda la institución. Los ámbitos trayecto,
  # curso y comisión se referencian por ID, sin clave foránea: sus tablas
  # llegan en H1 y la cascada la resuelve la aplicación.
  def change do
    create table(:role_assignments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :scope_type, :string, null: false
      add :scope_id, :uuid
      add :granted_by_id, :uuid

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:role_assignments, [:user_id])
    create index(:role_assignments, [:scope_type, :scope_id])

    execute(
      """
      CREATE UNIQUE INDEX role_assignments_unique_index
      ON #{prefix()}.role_assignments (user_id, role, scope_type, scope_id) NULLS NOT DISTINCT
      """,
      "DROP INDEX #{prefix()}.role_assignments_unique_index"
    )

    create constraint(:role_assignments, :scope_must_be_valid,
             check: """
             (scope_type = 'institution' AND scope_id IS NULL) OR
             (scope_type IN ('pathway', 'course', 'section') AND scope_id IS NOT NULL)
             """
           )
  end
end
