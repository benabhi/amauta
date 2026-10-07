defmodule Amauta.Repo.TenantMigrations.CreatePosts do
  use Ecto.Migration

  # Tablón del curso (RF-TAB-001 a 003 y 008). Una publicación va a todo el
  # curso (section_id nulo) o a una comisión. Hay un único borrador por
  # persona y curso, que se guarda solo mientras se escribe.
  def change do
    create table(:posts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :section_id, references(:course_sections, type: :uuid, on_delete: :nilify_all)
      add :body, :map
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime_usec
      add :edited_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:posts, [:course_id, :status, :published_at])

    create unique_index(:posts, [:course_id, :author_id],
             where: "status = 'draft'",
             name: :posts_one_draft_index
           )

    create constraint(:posts, :status_must_be_valid, check: "status IN ('draft', 'published')")
  end
end
