defmodule Amauta.Repo.TenantMigrations.CreatePeriodsAndPathways do
  use Ecto.Migration

  # Períodos lectivos (RF-INS-009), trayectos (RF-TRA-001) y sus etapas
  # (RF-TRA-002). Los cursos de cada etapa llegan con la tabla de cursos.
  def change do
    create table(:academic_periods, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :current, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:academic_periods, ["lower(name)"], name: :academic_periods_name_index)

    # A lo sumo un período actual por institución.
    create unique_index(:academic_periods, [:current],
             where: "current",
             name: :academic_periods_current_index
           )

    create constraint(:academic_periods, :dates_must_be_ordered, check: "ends_on >= starts_on")

    create table(:pathways, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :code, :citext
      add :slug, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:pathways, [:slug])
    create unique_index(:pathways, [:code])
    create index(:pathways, [:status])

    create constraint(:pathways, :status_must_be_valid,
             check: "status IN ('draft', 'published', 'archived')"
           )

    create table(:pathway_stages, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :pathway_id, references(:pathways, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Diferible: reordenar intercambia posiciones dentro de una transacción.
    execute(
      """
      ALTER TABLE #{prefix()}.pathway_stages
      ADD CONSTRAINT pathway_stages_position_index
      UNIQUE (pathway_id, position) DEFERRABLE INITIALLY DEFERRED
      """,
      "ALTER TABLE #{prefix()}.pathway_stages DROP CONSTRAINT pathway_stages_position_index"
    )
  end
end
