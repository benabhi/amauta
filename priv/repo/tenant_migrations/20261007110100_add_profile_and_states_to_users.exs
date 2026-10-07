defmodule Amauta.Repo.TenantMigrations.AddProfileAndStatesToUsers do
  use Ecto.Migration

  # Perfil (RF-USR-001) y estados de cuenta (RF-USR-003): invitada,
  # activa, suspendida y archivada.
  def change do
    alter table(:users) do
      add :preferred_name, :string
      add :timezone, :string
      add :invited_at, :utc_datetime
    end

    drop constraint(:users, :status_must_be_valid)

    create constraint(:users, :status_must_be_valid,
             check: "status IN ('invited', 'active', 'suspended', 'archived')"
           )

    create index(:users, [:status])

    # Búsqueda por nombre y email (pg_trgm, migración global).
    execute(
      """
      CREATE INDEX users_search_index ON #{prefix()}.users
      USING gin ((lower(first_name || ' ' || last_name || ' ' || email)) public.gin_trgm_ops)
      """,
      "DROP INDEX #{prefix()}.users_search_index"
    )
  end
end
