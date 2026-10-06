defmodule Amauta.AuthorizationTest do
  @moduledoc "Permisos efectivos con cascada y caché (RF-ROL-003, 004 y 005)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Authorization, Scope}
  alias Amauta.Authorization.{Roles, ScopeRef}

  # Un trayecto con un curso, y el curso con dos comisiones.
  setup do
    pathway = Ecto.UUID.generate()
    course = Ecto.UUID.generate()
    section_a = Ecto.UUID.generate()
    section_b = Ecto.UUID.generate()

    %{
      pathway: pathway,
      course: course,
      course_target: %ScopeRef{type: "course", id: course, parents: [{"pathway", pathway}]},
      section_a: section_a,
      section_a_target: %ScopeRef{
        type: "section",
        id: section_a,
        parents: [{"course", course}, {"pathway", pathway}]
      },
      section_b_target: %ScopeRef{
        type: "section",
        id: section_b,
        parents: [{"course", course}, {"pathway", pathway}]
      },
      other_course_target: %ScopeRef{type: "course", id: Ecto.UUID.generate()}
    }
  end

  describe "cascada" do
    test "un rol de institución aplica en cualquier ámbito", ctx do
      scope = member_scope("institution_admin")

      assert Authorization.can?(scope, "institution.users.manage")
      assert Authorization.can?(scope, "course.gradebook.edit", ctx.section_a_target)
      assert Authorization.can?(scope, "course.gradebook.edit", ctx.other_course_target)
    end

    test "un rol de trayecto aplica a sus cursos y comisiones, no a otros", ctx do
      scope = member_scope("pathway_coordinator", {"pathway", ctx.pathway})

      assert Authorization.can?(scope, "course.content.manage", ctx.course_target)
      assert Authorization.can?(scope, "course.content.manage", ctx.section_a_target)
      refute Authorization.can?(scope, "course.content.manage", ctx.other_course_target)
      refute Authorization.can?(scope, "institution.users.manage")
    end

    test "un rol de curso aplica a sus comisiones", ctx do
      scope = member_scope("teacher", {"course", ctx.course})

      assert Authorization.can?(scope, "course.submissions.grade", ctx.course_target)
      assert Authorization.can?(scope, "course.submissions.grade", ctx.section_b_target)
      refute Authorization.can?(scope, "course.submissions.grade", ctx.other_course_target)
    end

    test "un rol de comisión se limita a esa comisión", ctx do
      scope = member_scope("assistant", {"section", ctx.section_a})

      assert Authorization.can?(scope, "course.submissions.grade", ctx.section_a_target)
      refute Authorization.can?(scope, "course.submissions.grade", ctx.section_b_target)
      refute Authorization.can?(scope, "course.submissions.grade", ctx.course_target)
    end

    test "los permisos son la unión de todas las asignaciones aplicables", ctx do
      user = user_fixture()
      assign!(user, "observer", :institution)
      assign!(user, "student", {"course", ctx.course})
      scope = Scope.for_user(institution(), user)

      expected = MapSet.union(Roles.permissions("observer"), Roles.permissions("student"))
      assert Authorization.permissions(scope, ctx.course_target) == expected

      assert Authorization.permissions(scope, ctx.other_course_target) ==
               Roles.permissions("observer")
    end

    test "sin persona no hay permisos" do
      assert Authorization.permissions(Scope.for_institution(institution())) == MapSet.new()
      refute Authorization.can?(Scope.for_institution(institution()), "course.view")
    end
  end

  test "can?/3 falla con un permiso inexistente" do
    assert_raise ArgumentError, fn -> Authorization.can?(member_scope("teacher"), "no.existe") end
  end

  test "authorize/3 devuelve :ok o {:error, :forbidden}" do
    scope = member_scope("student")
    assert :ok = Authorization.authorize(scope, "course.view")
    assert {:error, :forbidden} = Authorization.authorize(scope, "course.gradebook.edit")
  end

  test "la caché se invalida al cambiar las asignaciones", ctx do
    user = user_fixture()
    scope = Scope.for_user(institution(), user)
    refute Authorization.can?(scope, "course.view", ctx.course_target)

    assignment = assign!(user, "student", {"course", ctx.course})
    assert Authorization.can?(scope, "course.view", ctx.course_target)

    {:ok, _} = Authorization.delete_assignment(scope, assignment)
    refute Authorization.can?(scope, "course.view", ctx.course_target)
  end

  describe "anti-escalada" do
    test "se puede dar un rol cuyos permisos ya se tienen en el ámbito", ctx do
      scope = member_scope("course_lead", {"course", ctx.course})

      assert Authorization.can_grant?(scope, "teacher", ctx.course_target)
      assert Authorization.can_grant?(scope, "student", ctx.course_target)
    end

    test "no se puede dar un rol con más permisos", ctx do
      scope = member_scope("teacher", {"course", ctx.course})

      refute Authorization.can_grant?(scope, "course_lead", ctx.course_target)
      refute Authorization.can_grant?(scope, "institution_admin", :institution)
    end

    test "no se puede dar un rol inexistente", ctx do
      refute Authorization.can_grant?(member_scope("institution_admin"), "god", ctx.course_target)
    end
  end
end
