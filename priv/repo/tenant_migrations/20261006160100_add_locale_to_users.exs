defmodule Amauta.Repo.TenantMigrations.AddLocaleToUsers do
  use Ecto.Migration

  # Idioma preferido de la persona; nulo = el de la institución (RF-I18N-004).
  def change do
    alter table(:users) do
      add :locale, :string
    end
  end
end
