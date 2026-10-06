defmodule Amauta.Repo do
  use AshPostgres.Repo,
    otp_app: :amauta

  import Ecto.Query

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions"]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  @impl true
  def min_pg_version do
    %Version{major: 18, minor: 0, patch: 0}
  end

  @doc "Schemas de todas las instituciones, para `mix ash_postgres.migrate --tenants`."
  @impl true
  def all_tenants do
    all(from(i in "institutions", prefix: "global", select: i.schema_name))
  end

  @doc """
  Rechaza toda consulta sin prefijo explícito (RNF-SEG-002). Ash ya exige
  la institución en los recursos multi-tenant; esto cubre las consultas
  de Ecto escritas a mano.
  """
  @impl true
  def prepare_query(_operation, query, opts) do
    if opts[:schema_migration] || opts[:prefix] || prefixed?(query) do
      {query, opts}
    else
      raise Amauta.MissingPrefixError, query: query
    end
  end

  defp prefixed?(%Ecto.Query{prefix: prefix}) when is_binary(prefix), do: true

  defp prefixed?(%Ecto.Query{from: from, joins: joins}) do
    from.prefix != nil and Enum.all?(joins, &(&1.prefix != nil or &1.source == nil))
  end
end

defmodule Amauta.MissingPrefixError do
  @moduledoc "Se intentó consultar la base sin indicar el schema (institución o global)."
  defexception [:query]

  @impl true
  def message(%{query: query}) do
    "query without an explicit prefix (institution or global): #{inspect(query)}"
  end
end
