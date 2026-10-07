defmodule Amauta.Repo.TenantMigrations.CreatePostReplies do
  use Ecto.Migration

  # Respuestas en hilo del tablón (RF-TAB-004): a una publicación o a otra
  # respuesta, con un solo nivel de anidación (parent_id apunta siempre a
  # una respuesta de primer nivel). La moderación oculta sin borrar
  # (RF-TAB-007), y silenciar impide publicar y responder en el curso.
  def change do
    alter table(:posts) do
      add :replies_enabled, :boolean, null: false, default: true
    end

    create table(:post_replies, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :post_id, references(:posts, type: :uuid, on_delete: :delete_all), null: false
      add :parent_id, references(:post_replies, type: :uuid, on_delete: :delete_all)
      add :author_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :body, :map, null: false
      add :edited_at, :utc_datetime_usec
      add :hidden_at, :utc_datetime_usec
      add :hidden_by_id, :uuid

      timestamps(type: :utc_datetime_usec)
    end

    create index(:post_replies, [:post_id, :inserted_at])
    create index(:post_replies, [:parent_id])

    create table(:feed_mutes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :muted_by_id, :uuid

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:feed_mutes, [:course_id, :user_id])
  end
end
