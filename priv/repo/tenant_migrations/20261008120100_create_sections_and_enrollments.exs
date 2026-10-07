defmodule Amauta.Repo.TenantMigrations.CreateSectionsAndEnrollments do
  use Ecto.Migration

  # Comisiones (RF-COM-001) y matrículas (RF-MAT-002). Cada matrícula activa
  # se refleja en una asignación de rol (la que usan los permisos), ligada
  # por `enrollment_id`: en el curso o, para el equipo docente de una
  # comisión, en la comisión (RF-COM-002). Dar de baja conserva la
  # matrícula como finalizada (RF-MAT-003).
  def change do
    create table(:course_sections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :schedule, :string
      add :room, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:course_sections, [:course_id])

    create unique_index(:course_sections, [:course_id, "lower(name)"],
             name: :course_sections_name_index
           )

    create table(:enrollments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :section_id, references(:course_sections, type: :uuid, on_delete: :nilify_all)
      add :role, :string, null: false
      add :status, :string, null: false, default: "active"
      add :origin, :string, null: false
      add :starts_on, :date
      add :ends_on, :date
      add :ended_at, :utc_datetime_usec
      add :enrolled_by_id, :uuid

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:enrollments, [:course_id, :user_id])
    create index(:enrollments, [:user_id])
    create index(:enrollments, [:section_id])

    create constraint(:enrollments, :status_must_be_valid,
             check: "status IN ('active', 'pending', 'suspended', 'ended')"
           )

    create constraint(:enrollments, :origin_must_be_valid,
             check: "origin IN ('manual', 'csv', 'pathway', 'code')"
           )

    alter table(:role_assignments) do
      add :enrollment_id, references(:enrollments, type: :uuid, on_delete: :delete_all)
    end

    create index(:role_assignments, [:enrollment_id])

    # Las asignaciones en un curso que ya existían pasan a ser matrículas
    # manuales (una por persona: la primera, si había varias).
    execute(
      """
      INSERT INTO #{prefix()}.enrollments
        (id, course_id, user_id, role, status, origin, enrolled_by_id, inserted_at, updated_at)
      SELECT DISTINCT ON (a.scope_id, a.user_id)
        gen_random_uuid(), a.scope_id, a.user_id, a.role, 'active', 'manual', a.granted_by_id,
        a.inserted_at, a.inserted_at
      FROM #{prefix()}.role_assignments a
      JOIN #{prefix()}.courses c ON c.id = a.scope_id
      WHERE a.scope_type = 'course'
      ORDER BY a.scope_id, a.user_id, a.inserted_at
      """,
      ""
    )

    execute(
      """
      UPDATE #{prefix()}.role_assignments a
      SET enrollment_id = e.id
      FROM #{prefix()}.enrollments e
      WHERE a.scope_type = 'course' AND a.scope_id = e.course_id
        AND a.user_id = e.user_id AND a.role = e.role
      """,
      ""
    )
  end
end
