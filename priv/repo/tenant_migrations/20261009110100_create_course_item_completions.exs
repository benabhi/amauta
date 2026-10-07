defmodule Amauta.Repo.TenantMigrations.CreateCourseItemCompletions do
  use Ecto.Migration

  # Seguimiento de finalización (RF-CON-006): qué elementos marcó cada
  # persona como hechos. En H3, entregar o rendir también los marca.
  def change do
    create table(:course_item_completions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :item_id, references(:course_items, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :completed_at, :utc_datetime_usec, null: false
    end

    create unique_index(:course_item_completions, [:item_id, :user_id])
    create index(:course_item_completions, [:course_id, :user_id])
  end
end
