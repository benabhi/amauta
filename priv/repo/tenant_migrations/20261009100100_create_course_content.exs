defmodule Amauta.Repo.TenantMigrations.CreateCourseContent do
  use Ecto.Migration

  # Contenido del curso (RF-CON-001, 002, 004 y 005): unidades ordenadas y,
  # dentro de cada una, elementos (en el MVP, páginas y materiales; tareas y
  # evaluaciones se suman en H3). Unidades y elementos pueden estar visibles,
  # ocultos o programados (`publish_at`).
  def change do
    create table(:course_units, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :starts_on, :date
      add :ends_on, :date
      add :visibility, :string, null: false, default: "visible"
      add :publish_at, :utc_datetime_usec
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:course_units, [:course_id, :position])

    create constraint(:course_units, :unit_visibility_must_be_valid,
             check: "visibility IN ('visible', 'hidden', 'scheduled')"
           )

    create constraint(:course_units, :unit_scheduled_needs_date,
             check: "visibility <> 'scheduled' OR publish_at IS NOT NULL"
           )

    create table(:course_items, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :unit_id, references(:course_units, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body, :map
      add :url, :string, size: 2048
      add :visibility, :string, null: false, default: "visible"
      add :publish_at, :utc_datetime_usec
      add :position, :integer, null: false, default: 0
      add :created_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:course_items, [:unit_id, :position])
    create index(:course_items, [:course_id])

    create constraint(:course_items, :item_kind_must_be_valid,
             check: "kind IN ('page', 'material')"
           )

    create constraint(:course_items, :item_visibility_must_be_valid,
             check: "visibility IN ('visible', 'hidden', 'scheduled')"
           )

    create constraint(:course_items, :item_scheduled_needs_date,
             check: "visibility <> 'scheduled' OR publish_at IS NOT NULL"
           )

    # Archivos de un material (propósito `content_material`).
    create table(:course_item_files, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :item_id, references(:course_items, type: :uuid, on_delete: :delete_all), null: false
      add :file_id, references(:files, type: :uuid, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:course_item_files, [:file_id])
    create index(:course_item_files, [:item_id])
  end
end
