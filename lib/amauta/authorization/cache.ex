defmodule Amauta.Authorization.Cache do
  @moduledoc """
  Caché en ETS de las asignaciones de rol de cada persona, versionada por
  institución (ERS 8.7). Cualquier cambio de roles en una institución sube
  su versión y deja obsoletas todas sus entradas, sin recorrerlas.

  Las lecturas van directo a ETS desde el proceso que pregunta; el proceso
  de este módulo solo es dueño de la tabla.
  """
  use GenServer

  @table :amauta_authorization_cache

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc """
  Devuelve el valor cacheado de la persona en la institución o lo calcula
  con `fun` y lo guarda con la versión vigente.
  """
  def fetch(institution_id, user_id, fun) when is_function(fun, 0) do
    version = version(institution_id)
    key = {:assignments, institution_id, user_id}

    case :ets.lookup(@table, key) do
      [{^key, ^version, value}] ->
        value

      _ ->
        value = fun.()
        :ets.insert(@table, {key, version, value})
        value
    end
  end

  @doc "Invalida todas las entradas de una institución."
  def invalidate(institution_id) do
    :ets.update_counter(@table, {:version, institution_id}, 1, {{:version, institution_id}, 0})
    :ok
  end

  defp version(institution_id) do
    case :ets.lookup(@table, {:version, institution_id}) do
      [{_key, version}] -> version
      [] -> 0
    end
  end
end
