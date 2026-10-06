defmodule Amauta.Repo do
  use Ecto.Repo,
    otp_app: :amauta,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Rechaza toda consulta sin prefijo explícito (RNF-SEG-002).

  Las tablas globales declaran `@schema_prefix "global"` y las de cada
  institución reciben el prefijo de su schema, así que una consulta sin
  prefijo es siempre un error de programación.
  """
  @impl true
  def prepare_query(_operation, query, opts) do
    if opts[:schema_migration] || opts[:prefix] || prefixed?(query) do
      {query, opts}
    else
      raise Amauta.Tenancy.MissingPrefixError, query: query
    end
  end

  defp prefixed?(%Ecto.Query{prefix: prefix}) when is_binary(prefix), do: true

  defp prefixed?(%Ecto.Query{from: from, joins: joins}) do
    from.prefix != nil and Enum.all?(joins, &(&1.prefix != nil or &1.source == nil))
  end
end
