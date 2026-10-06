defmodule Amauta.Tenancy.Migrator do
  @moduledoc """
  Migraciones de los schemas de institución (RF-ADM-006).

  Corren en paralelo con concurrencia acotada. Un fallo en una institución
  no bloquea a las demás: el resultado de cada una queda registrado en
  `global.institutions` (`schema_version`, `migration_error`, `migrated_at`)
  y se puede reintentar.

  Las migraciones se compilan una sola vez por VM y se pasan a
  `Ecto.Migrator` como lista, para que los procesos en paralelo no
  recompilen los mismos módulos.
  """
  require Logger

  alias Amauta.Platform.Institution
  alias Amauta.Repo

  @default_concurrency 4

  @doc """
  Concurrencia por defecto. Cada migración en curso usa dos conexiones del
  pool: con la aplicación en marcha, no conviene pasar de la mitad del pool.
  """
  def default_concurrency, do: @default_concurrency

  @type result :: {:ok, version :: integer() | nil} | {:error, String.t()}

  @doc "Migra todas las instituciones. Devuelve `[{institución, resultado}]`."
  @spec migrate_all(keyword()) :: [{Institution.t(), result()}]
  def migrate_all(opts \\ []) do
    # Compila las migraciones antes de lanzar las tareas en paralelo.
    migrations()

    Amauta.Platform.list_institutions()
    |> Task.async_stream(&{&1, migrate(&1)},
      max_concurrency: Keyword.get(opts, :concurrency, @default_concurrency),
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, pair} -> pair end)
  end

  @doc "Migra una institución y registra el resultado."
  @spec migrate(Institution.t()) :: result()
  def migrate(%Institution{schema_name: schema} = institution) do
    result = migrate_schema(schema)

    attrs =
      case result do
        {:ok, version} -> %{schema_version: version, migration_error: nil}
        {:error, message} -> %{schema_version: current_version(schema), migration_error: message}
      end

    institution
    |> Institution.migration_changeset(Map.put(attrs, :migrated_at, DateTime.utc_now()))
    |> Repo.update!()

    result
  end

  @doc "Crea el schema si hace falta y le aplica las migraciones pendientes."
  @spec migrate_schema(String.t()) :: result()
  def migrate_schema(schema) do
    validate_schema_name!(schema)
    Repo.query!(~s(CREATE SCHEMA IF NOT EXISTS "#{schema}"))
    Ecto.Migrator.run(Repo, migrations(), :up, all: true, prefix: schema, log: false)
    {:ok, current_version(schema)}
  rescue
    error ->
      Logger.error("tenant migration failed for #{schema}: #{Exception.message(error)}")
      {:error, Exception.message(error)}
  end

  @doc "Última migración aplicada a un schema, o `nil`."
  def current_version(schema) do
    Repo
    |> Ecto.Migrator.migrated_versions(prefix: schema)
    |> Enum.max(fn -> nil end)
  rescue
    _ -> nil
  end

  @doc "Migraciones de institución como `[{versión, módulo}]`."
  def migrations do
    migrations_path()
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&load/1)
  end

  def migrations_path, do: Application.app_dir(:amauta, "priv/repo/tenant_migrations")

  defp load(file) do
    key = {__MODULE__, file}

    case :persistent_term.get(key, nil) do
      nil ->
        :global.trans({key, self()}, fn ->
          :persistent_term.get(key, nil) || compile(file, key)
        end)

      loaded ->
        loaded
    end
  end

  # Compila un archivo de migración una sola vez por VM, aunque varios
  # procesos lo pidan al mismo tiempo: el lock de `load/1` los serializa.
  defp compile(file, key) do
    {version, _rest} = file |> Path.basename() |> Integer.parse()

    module =
      file
      |> Code.compile_file()
      |> Enum.map(&elem(&1, 0))
      |> Enum.find(&function_exported?(&1, :__migration__, 0))

    :persistent_term.put(key, {version, module})
    {version, module}
  end

  defp validate_schema_name!(schema) do
    if not Regex.match?(~r/^inst_[a-z0-9_]+$/, schema) do
      raise ArgumentError, "invalid institution schema name: #{inspect(schema)}"
    end
  end
end
