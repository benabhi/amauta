defmodule Amauta.Repo.TenantMigrations.CreateUserDevices do
  use Ecto.Migration

  # Dispositivos desde los que cada persona inició sesión, para avisarle
  # cuando entra desde uno nuevo (RF-AUT-006).
  def change do
    create table(:user_devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :fingerprint, :binary, null: false
      add :user_agent, :string
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_devices, [:user_id, :fingerprint])
  end
end
