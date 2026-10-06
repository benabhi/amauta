defmodule Amauta.Repo.TenantMigrations.AddHashChainToAuditEvents do
  use Ecto.Migration

  # Encadenamiento de hashes de la auditoría (ERS 8.10): cada evento guarda
  # el hash del anterior y el suyo, así cualquier alteración se detecta.
  def change do
    alter table(:audit_events) do
      add :sequence, :bigint
      add :prev_hash, :binary
      add :hash, :binary
    end

    create unique_index(:audit_events, [:sequence])
  end
end
