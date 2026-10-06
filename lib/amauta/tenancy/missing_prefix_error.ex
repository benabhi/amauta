defmodule Amauta.Tenancy.MissingPrefixError do
  @moduledoc "Se intentó consultar la base sin indicar el schema (institución o global)."
  defexception [:query]

  @impl true
  def message(%{query: query}) do
    "query without an explicit prefix (institution or global): #{inspect(query)}"
  end
end
