defmodule Amauta.Repo.Migrations.AddTerminologyToInstitutions do
  use Ecto.Migration

  # Terminología configurable (ERS 4.9): un preset del Anexo E y los ajustes
  # de la institución sobre él.
  def change do
    alter table(:institutions, prefix: "global") do
      add :terminology_preset, :string, null: false, default: "generic"
      add :terminology, :map, null: false, default: %{}
    end
  end
end
