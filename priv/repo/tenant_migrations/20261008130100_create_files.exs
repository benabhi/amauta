defmodule Amauta.Repo.TenantMigrations.CreateFiles do
  use Ecto.Migration

  # Archivos subidos directo al almacenamiento (RF-ARC-001 a 004 y 007).
  # La fila nace `pending` al pedir la subida y pasa a `ready` cuando se
  # verifica el objeto y su tipo real; si no pasa la verificación, queda
  # `rejected` y el objeto se borra. `purpose` dice para qué es (por
  # ejemplo, la foto de perfil) y de él salen los límites y los permisos.
  def change do
    create table(:files, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :purpose, :string, null: false
      add :owner_id, :uuid
      add :key, :string, null: false
      add :filename, :string, null: false
      add :declared_type, :string
      add :content_type, :string
      add :size, :bigint, null: false
      add :status, :string, null: false, default: "pending"
      add :rejection_reason, :string
      add :upload_id, :string
      add :uploaded_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:files, [:key])
    create index(:files, [:purpose, :owner_id])
    create index(:files, [:uploaded_by_id, :status])

    create constraint(:files, :status_must_be_valid,
             check: "status IN ('pending', 'ready', 'rejected')"
           )

    # Foto de perfil (RF-USR-001).
    alter table(:users) do
      add :avatar_file_id, references(:files, type: :uuid, on_delete: :nilify_all)
    end
  end
end
