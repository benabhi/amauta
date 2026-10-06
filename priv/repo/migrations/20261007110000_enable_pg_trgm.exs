defmodule Amauta.Repo.Migrations.EnablePgTrgm do
  use Ecto.Migration

  # Búsqueda aproximada por texto (ERS 8.12). La extensión es de toda la
  # base; las tablas de cada institución usan sus operadores.
  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
