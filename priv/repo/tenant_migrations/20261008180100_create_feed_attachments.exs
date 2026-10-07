defmodule Amauta.Repo.TenantMigrations.CreateFeedAttachments do
  use Ecto.Migration

  # Archivos adjuntos a publicaciones y respuestas del tablón (RF-TAB-005).
  # Cada archivo pertenece a una sola publicación o respuesta; al borrarla,
  # se van sus vínculos (los objetos se limpian aparte).
  def change do
    create table(:feed_attachments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :post_id, references(:posts, type: :uuid, on_delete: :delete_all)
      add :reply_id, references(:post_replies, type: :uuid, on_delete: :delete_all)
      add :file_id, references(:files, type: :uuid, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:feed_attachments, [:file_id])
    create index(:feed_attachments, [:post_id])
    create index(:feed_attachments, [:reply_id])

    create constraint(:feed_attachments, :attached_to_one,
             check: "(post_id IS NULL) <> (reply_id IS NULL)"
           )
  end
end
