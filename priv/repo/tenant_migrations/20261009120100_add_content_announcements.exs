defmodule Amauta.Repo.TenantMigrations.AddContentAnnouncements do
  use Ecto.Migration

  # Tarjetas del tablón para el contenido (ERS 4.3): un elemento puede
  # avisar en el tablón cuando el estudiantado empieza a verlo (al crearlo
  # visible, al mostrarlo o al llegar su fecha programada). La tarjeta es
  # una publicación de tipo `content` que apunta al elemento.
  def change do
    alter table(:course_items) do
      add :announce, :boolean, null: false, default: false
      add :announced_at, :utc_datetime_usec
    end

    alter table(:posts) do
      add :kind, :string, null: false, default: "post"
      add :item_id, references(:course_items, type: :uuid, on_delete: :delete_all)
    end

    create unique_index(:posts, [:item_id], where: "item_id IS NOT NULL")

    create constraint(:posts, :post_kind_must_be_valid,
             check: "kind IN ('post', 'content') AND ((kind = 'content') = (item_id IS NOT NULL))"
           )
  end
end
