defmodule Amauta.Tenancy do
  @moduledoc """
  Un schema de PostgreSQL por institución (ERS 8.3). El prefijo viaja en
  cada consulta; nunca se usa `search_path`.
  """
  alias Amauta.Platform.Institution
  alias Amauta.Repo

  @doc "Prefijo de Ecto de una institución o de un Scope."
  def prefix(%Institution{schema_name: schema}), do: schema
  def prefix(%{institution: %Institution{} = institution}), do: prefix(institution)

  @doc "Opciones de Repo para operar dentro de la institución."
  def opts(tenant), do: [prefix: prefix(tenant)]

  @doc "Registra una institución, crea su schema y le aplica las migraciones."
  def create_institution(attrs) do
    attrs = Map.put_new_lazy(attrs, :schema_name, &generate_schema_name/0)

    with {:ok, institution} <- Repo.insert(Institution.changeset(%Institution{}, attrs)) do
      create_schema!(institution.schema_name)
      {:ok, institution}
    end
  end

  @doc "Crea el schema (si no existe) y aplica las migraciones de institución."
  def create_schema!(schema_name) do
    Repo.query!(~s(CREATE SCHEMA IF NOT EXISTS "#{schema_name}"))
    migrate!(schema_name)
  end

  def migrate!(schema_name) do
    # Las migraciones se cargan una vez por schema: redefinir el módulo es esperado.
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Ecto.Migrator.run(Repo, migrations_path(), :up, all: true, prefix: schema_name, log: false)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  defp migrations_path, do: Application.app_dir(:amauta, "priv/repo/tenant_migrations")

  defp generate_schema_name do
    "inst_" <> (:crypto.strong_rand_bytes(5) |> Base.encode32(case: :lower, padding: false))
  end
end
