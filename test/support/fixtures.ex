defmodule Amauta.Fixtures do
  @moduledoc "Datos de prueba."
  alias Amauta.{Accounts, Authorization, Catalog, Repo, Scope}
  alias Amauta.Platform.Institution

  @tenant_schemas ~w(inst_test_a inst_test_b)

  def tenant_schemas, do: @tenant_schemas

  def institution_fixture(schema_name \\ "inst_test_a") do
    slug = String.replace(schema_name, "_", "-")

    %Institution{}
    |> Institution.changeset(%{slug: slug, name: "Institución #{slug}", schema_name: schema_name})
    |> Repo.insert!()
  end

  def user_fixture(institution, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Enum.into(attrs, %{name: "Persona #{n}", email: "persona#{n}@example.test"})
    {:ok, user} = Accounts.create_user(institution, attrs)
    user
  end

  def course_fixture(institution, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Enum.into(attrs, %{slug: "curso-#{n}", name: "Curso #{n}"})
    {:ok, course} = Catalog.create_course(institution, attrs)
    course
  end

  @doc "Crea una persona con el rol dado; sin curso, el ámbito es la institución."
  def member_fixture(institution, role, course \\ nil) do
    user = user_fixture(institution)

    {:ok, _} =
      Authorization.assign_role(institution, %{
        user_id: user.id,
        role: role,
        course_id: course && course.id
      })

    user
  end

  def scope_fixture(institution, user), do: Scope.for_user(institution, user)
end
