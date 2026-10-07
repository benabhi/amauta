defmodule Amauta.Repo.Migrations.CreateEmailSuppressions do
  use Ecto.Migration

  # Lista de supresión del correo (RF-EML-003): direcciones con fallos
  # permanentes. Después de varios rebotes, no se les envía más. Es de la
  # instancia (el servidor SMTP es uno), en el schema global.
  def change do
    create table(:email_suppressions, prefix: "global", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :address, :citext, null: false
      add :bounces, :integer, null: false, default: 0
      add :last_error, :text
      add :suppressed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:email_suppressions, [:address], prefix: "global")
  end
end
