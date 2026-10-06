defmodule Amauta.Repo.TenantMigrations.CreateCourses do
  use Ecto.Migration

  # Cursos (RF-CUR-001, RF-CUR-005 y RF-CUR-007). Un curso puede estar
  # suelto o pertenecer a un trayecto propietario (reglas R2 y R3), en una
  # de sus etapas, como obligatorio u optativo (RF-TRA-002). Los cursos
  # compartidos por referencia entre trayectos llegan en V1.
  def change do
    create table(:courses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :code, :citext
      add :slug, :string, null: false
      add :description, :text
      add :icon, :string, null: false, default: "book-open"
      add :color, :string, null: false, default: "anil"
      add :status, :string, null: false, default: "draft"
      add :archived_at, :utc_datetime_usec
      add :period_id, references(:academic_periods, type: :uuid, on_delete: :restrict)
      add :pathway_id, references(:pathways, type: :uuid, on_delete: :restrict)
      add :stage_id, references(:pathway_stages, type: :uuid, on_delete: :nilify_all)
      add :required, :boolean, null: false, default: true
      add :enrollment_code, :citext, null: false
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:courses, [:slug])
    create unique_index(:courses, [:enrollment_code])
    create index(:courses, [:status])
    create index(:courses, [:period_id])
    create index(:courses, [:pathway_id])
    create index(:courses, [:stage_id])

    create constraint(:courses, :status_must_be_valid,
             check: "status IN ('draft', 'published', 'archived')"
           )

    # Sin trayecto no hay etapa.
    create constraint(:courses, :stage_needs_pathway,
             check: "stage_id IS NULL OR pathway_id IS NOT NULL"
           )
  end
end
