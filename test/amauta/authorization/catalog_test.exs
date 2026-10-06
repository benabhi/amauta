defmodule Amauta.Authorization.CatalogTest do
  @moduledoc "Catálogo de permisos (Anexo B) y roles de sistema (Anexo C)."
  use ExUnit.Case, async: true

  alias Amauta.Authorization.{Permissions, Roles}

  describe "permisos" do
    test "las claves son únicas y siguen la convención <ámbito>.<recurso>.<acción>" do
      keys = Permissions.keys()
      assert keys == Enum.uniq(keys)

      for key <- keys do
        assert key =~ ~r/^(platform|institution|pathway|course|self)\.[a-z_]+(\.[a-z_]+)?$/,
               "clave inválida: #{key}"
      end
    end

    test "cada permiso tiene riesgo y descripción" do
      for key <- Permissions.keys() do
        assert %{risk: risk, description: description} = Permissions.get(key)
        assert risk in [:low, :medium, :high]
        assert String.length(description) > 0
      end
    end

    test "fetch!/1 falla con una clave desconocida" do
      assert_raise ArgumentError, ~r/unknown permission/, fn ->
        Permissions.fetch!("course.feed.postt")
      end
    end
  end

  describe "roles de sistema" do
    test "existen los ocho del Anexo C" do
      assert Roles.keys() ==
               ~w(institution_admin academic_management pathway_coordinator course_lead
                  teacher assistant student observer)
    end

    test "ningún rol de institución incluye permisos de plataforma ni personales" do
      for role <- Roles.keys(), permission <- Roles.permissions(role) do
        refute String.starts_with?(permission, ["platform.", "self."]),
               "#{role} incluye #{permission}"
      end
    end

    test "todos los roles ven el curso" do
      for role <- Roles.keys(), do: assert("course.view" in Roles.permissions(role))
    end

    test "solo los estudiantes entregan y rinden" do
      for role <- Roles.keys() do
        assert "course.submissions.create_own" in Roles.permissions(role) == (role == "student")
        assert "course.attempts.create_own" in Roles.permissions(role) == (role == "student")
      end
    end

    test "estudiantes, ayudantes y observadores no editan notas" do
      for role <- ~w(student assistant observer) do
        refute "course.gradebook.edit" in Roles.permissions(role)
      end
    end

    test "solo la administración configura la institución y sus roles" do
      for role <- Roles.keys(), role != "institution_admin" do
        refute "institution.settings.update" in Roles.permissions(role)
        refute "institution.roles.manage" in Roles.permissions(role)
      end
    end

    test "la docencia es un subconjunto de la docencia responsable" do
      assert MapSet.subset?(Roles.permissions("teacher"), Roles.permissions("course_lead"))
    end
  end
end
