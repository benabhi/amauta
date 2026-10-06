defmodule Amauta.Fixtures do
  @moduledoc "Datos de prueba."
  alias Amauta.{Accounts, Authorization, Catalog, Scope}

  @tenant_schemas ~w(inst_test_a inst_test_b)

  def tenant_schemas, do: @tenant_schemas

  # Se inserta la fila directamente: tanto la acción como Ash.Seed disparan
  # `manage_tenant`, que vuelve a aplicar todas las migraciones y falla con
  # el schema ya creado en test_helper.exs.
  def institution_fixture(schema_name \\ "inst_test_a") do
    slug = String.replace(schema_name, "_", "-")
    now = DateTime.utc_now()

    Amauta.Repo.insert_all(
      "institutions",
      [
        %{
          id: Ecto.UUID.dump!(Ash.UUIDv7.generate()),
          slug: slug,
          name: "Institución #{slug}",
          schema_name: schema_name,
          inserted_at: now,
          updated_at: now
        }
      ],
      prefix: "global"
    )

    Amauta.Platform.get_institution_by_slug!(slug)
  end

  def user_fixture(institution, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Enum.into(attrs, %{name: "Persona #{n}", email: "persona#{n}@example.test"})
    Accounts.create_user!(attrs, tenant: institution, authorize?: false)
  end

  def course_fixture(institution, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Enum.into(attrs, %{slug: "curso-#{n}", name: "Curso #{n}"})
    Catalog.create_course!(attrs, tenant: institution, authorize?: false)
  end

  @doc "Crea una persona con el rol dado; sin curso, el ámbito es la institución."
  def member_fixture(institution, role, course \\ nil) do
    user = user_fixture(institution)

    Authorization.assign_role!(
      %{user_id: user.id, role: role, course_id: course && course.id},
      tenant: institution,
      authorize?: false
    )

    user
  end

  def scope_fixture(institution, user), do: Scope.for_user(institution, user)
end
