defmodule Amauta.Repo.Migrations.EnableCitext do
  use Ecto.Migration

  # Texto sin distinción de mayúsculas para los emails. La extensión es de
  # toda la base; las tablas de cada institución usan el tipo.
  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"
  end
end
