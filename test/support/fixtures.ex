defmodule Amauta.Fixtures do
  @moduledoc "Datos de prueba."
  alias Amauta.Platform.Institution
  alias Amauta.Repo

  @tenant_schemas ~w(inst_test_a inst_test_b)

  @doc "Schemas ya migrados por `test_helper.exs`."
  def tenant_schemas, do: @tenant_schemas

  @doc """
  Registra una institución sobre uno de los schemas de prueba.

  Los tests en paralelo insertan las mismas filas (índices únicos): si un
  test usa las dos instituciones, tiene que crear siempre primero
  `inst_test_a` y después `inst_test_b`, o puede haber deadlocks.
  """
  def institution_fixture(schema_name \\ "inst_test_a", attrs \\ %{}) do
    slug = String.replace(schema_name, "_", "-")

    %Institution{}
    |> Institution.changeset(Enum.into(attrs, %{slug: slug, name: "Institución #{slug}"}))
    |> Ecto.Changeset.put_change(:schema_name, schema_name)
    |> Repo.insert!()
  end
end
