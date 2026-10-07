defmodule Amauta.Repo.TenantMigrations.AddPinsToPosts do
  use Ecto.Migration

  # Publicaciones fijadas (RF-TAB-006): varias por curso, con orden manual y
  # vencimiento opcional. Vencida, deja de contar como fijada sin que nadie
  # la toque.
  def change do
    alter table(:posts) do
      add :pinned_at, :utc_datetime_usec
      add :pin_position, :integer
      add :pin_expires_at, :utc_datetime_usec
      add :pinned_by_id, :uuid
    end

    create index(:posts, [:course_id, :pin_position], where: "pinned_at IS NOT NULL")
  end
end
