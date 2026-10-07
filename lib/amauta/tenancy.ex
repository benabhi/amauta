defmodule Amauta.Tenancy do
  @moduledoc """
  Un schema de PostgreSQL por institución (ERS 8.3). El prefijo viaja en
  cada consulta; nunca se usa `search_path`, así el pool es compartido.

  Toda función de dominio que toca tablas de institución recibe un «tenant»:
  la institución o un `Amauta.Scope`, y lo convierte con `opts/1`.
  """
  alias Amauta.Platform.Institution
  alias Amauta.Repo
  alias Amauta.Tenancy.Migrator

  @type tenant :: Institution.t() | %{institution: Institution.t()}

  @doc "Prefijo de Ecto de una institución o de un Scope."
  @spec prefix(tenant()) :: String.t()
  def prefix(%Institution{schema_name: schema}), do: schema
  def prefix(%{institution: %Institution{} = institution}), do: prefix(institution)

  @doc "Opciones de Repo para operar dentro de la institución."
  @spec opts(tenant()) :: keyword()
  def opts(tenant), do: [prefix: prefix(tenant)]

  @doc """
  Alta de una institución (RF-ADM-002): la registra, crea su schema y le
  aplica las migraciones. Si la migración falla, la institución queda
  registrada con el error y se puede reintentar con `Migrator.migrate/1`.
  """
  @spec create_institution(map()) ::
          {:ok, Institution.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:migration_failed, Institution.t(), String.t()}}
  def create_institution(attrs) do
    with {:ok, institution} <- Repo.insert(Institution.create_changeset(%Institution{}, attrs)) do
      case Migrator.migrate(institution) do
        {:ok, _version} -> {:ok, Repo.reload!(institution)}
        {:error, message} -> {:error, {:migration_failed, Repo.reload!(institution), message}}
      end
    end
  end
end
