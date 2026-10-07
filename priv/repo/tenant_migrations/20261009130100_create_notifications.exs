defmodule Amauta.Repo.TenantMigrations.CreateNotifications do
  use Ecto.Migration

  # Notificaciones (C12): una fila por persona y aviso. Las no leídas del
  # mismo grupo («3 respuestas nuevas en…») se suman en una sola fila
  # (`group_key`, `count`). `email_pending` marca las que esperan salir por
  # email, agrupadas (C13).
  def change do
    create table(:notifications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all)
      add :actor_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :data, :map, null: false, default: %{}
      add :url, :string, size: 2048
      add :reason, :string, null: false
      add :group_key, :string, null: false
      add :count, :integer, null: false, default: 1
      add :read_at, :utc_datetime_usec
      add :email_pending, :boolean, null: false, default: false
      add :emailed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notifications, [:user_id, :updated_at])

    create index(:notifications, [:user_id],
             where: "read_at IS NULL",
             name: :notifications_unread_index
           )

    create unique_index(:notifications, [:user_id, :group_key],
             where: "read_at IS NULL",
             name: :notifications_unread_group_index
           )

    create index(:notifications, [:user_id],
             where: "email_pending",
             name: :notifications_email_pending_index
           )

    # Preferencias de cada persona (RF-NOT-004, RF-EML-005): sin fila, vale
    # el valor por defecto de la instancia (`Amauta.Notifications.Catalog`).
    create table(:notification_preferences, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :channel, :string, null: false
      add :enabled, :boolean, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_preferences, [:user_id, :event, :channel])

    create constraint(:notification_preferences, :channel_must_be_valid,
             check: "channel IN ('platform', 'email')"
           )
  end
end
