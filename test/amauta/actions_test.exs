defmodule Amauta.ActionsTest do
  @moduledoc "Capa de acciones: validación, autorización, auditoría y catálogo."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Authorization, Scope}
  alias Amauta.Authorization.Actions.{AssignRole, RevokeRole}
  alias Amauta.Authorization.RoleAssignment

  setup do
    %{course: Ecto.UUID.generate(), user: user_fixture()}
  end

  defp assign_params(user, role, type, id \\ nil) do
    %{"user_id" => user.id, "role" => role, "scope_type" => type, "scope_id" => id}
  end

  describe "AssignRole" do
    test "la administración asigna un rol y queda auditado", %{course: course, user: user} do
      admin = member_scope("institution_admin")

      assert {:ok, %RoleAssignment{} = assignment} =
               Actions.run(AssignRole, admin, assign_params(user, "teacher", "course", course))

      assert assignment.granted_by_id == admin.user.id
      assert [%{role: "teacher"}] = Authorization.list_assignments(admin, user.id)

      assert [event] = Audit.list_events(institution())
      assert event.action == "authorization.role_assignment.create"
      assert event.actor_id == admin.user.id
      assert event.subject_id == assignment.id
      assert event.metadata["role"] == "teacher"
    end

    test "los nuevos permisos valen enseguida", %{course: course, user: user} do
      {:ok, _} =
        Actions.run(
          AssignRole,
          member_scope("institution_admin"),
          assign_params(user, "student", "course", course)
        )

      target = Authorization.target("course", course)
      assert Authorization.can?(Scope.for_user(institution(), user), "course.view", target)
    end

    test "valida los parámetros", %{user: user} do
      admin = member_scope("institution_admin")

      assert {:error, changeset} = Actions.run(AssignRole, admin, %{})
      assert %{user_id: _, role: _, scope_type: _} = errors_on(changeset)

      assert {:error, changeset} =
               Actions.run(AssignRole, admin, assign_params(user, "god", "institution"))

      assert %{role: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} =
               Actions.run(AssignRole, admin, assign_params(user, "teacher", "course"))

      assert %{scope_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "una persona inexistente es un error de validación" do
      admin = member_scope("institution_admin")
      ghost = %{id: Ecto.UUID.generate()}

      assert {:error, changeset} =
               Actions.run(AssignRole, admin, assign_params(ghost, "teacher", "institution"))

      assert %{user_id: ["does not exist"]} = errors_on(changeset)
    end

    test "no se repite una asignación", %{user: user} do
      admin = member_scope("institution_admin")
      params = assign_params(user, "observer", "institution")

      assert {:ok, _} = Actions.run(AssignRole, admin, params)
      assert {:error, changeset} = Actions.run(AssignRole, admin, params)
      assert %{user_id: ["already assigned"]} = errors_on(changeset)
    end

    test "sin el permiso del ámbito está prohibido", %{course: course, user: user} do
      for scope <- [
            member_scope("teacher", {"course", course}),
            Scope.for_institution(institution())
          ] do
        assert {:error, :forbidden} =
                 Actions.run(AssignRole, scope, assign_params(user, "student", "course", course))
      end
    end

    test "anti-escalada: no se da un rol con permisos que uno no tiene",
         %{course: course, user: user} do
      # Gestión académica matricula en cualquier curso, pero no edita notas.
      scope = member_scope("academic_management")

      assert {:ok, _} =
               Actions.run(AssignRole, scope, assign_params(user, "student", "course", course))

      assert {:error, :forbidden} =
               Actions.run(AssignRole, scope, assign_params(user, "teacher", "course", course))
    end

    test "lo prohibido o inválido no deja auditoría", %{course: course, user: user} do
      Actions.run(
        AssignRole,
        member_scope("student"),
        assign_params(user, "teacher", "course", course)
      )

      Actions.run(AssignRole, member_scope("institution_admin"), %{})

      assert [] = Audit.list_events(institution())
    end
  end

  describe "RevokeRole" do
    test "quita la asignación y queda auditado", %{user: user} do
      admin = member_scope("institution_admin")
      assignment = assign!(user, "observer", :institution)

      assert {:ok, _} = Actions.run(RevokeRole, admin, %{"assignment_id" => assignment.id})
      assert [] = Authorization.list_assignments(admin, user.id)

      assert [%{action: "authorization.role_assignment.delete"}] =
               Audit.list_events(institution())
    end

    test "una asignación inexistente da :not_found" do
      admin = member_scope("institution_admin")

      assert {:error, :not_found} =
               Actions.run(RevokeRole, admin, %{"assignment_id" => Ecto.UUID.generate()})
    end

    test "no se quita un rol que uno no podría dar", %{user: user} do
      assignment = assign!(user, "institution_admin", :institution)

      assert {:error, :forbidden} =
               Actions.run(RevokeRole, member_scope("academic_management"), %{
                 "assignment_id" => assignment.id
               })
    end
  end

  describe "cast/2" do
    test "un campo vacío llega como nil explícito, para poder vaciarlo" do
      action = Amauta.Accounts.Actions.UpdateUser
      id = Ecto.UUID.generate()

      assert {:ok, input} =
               Actions.cast(action, %{"user_id" => id, "preferred_name" => "  ", "timezone" => ""})

      assert input == %{user_id: id, preferred_name: nil, timezone: nil}
      assert {:ok, %{user_id: ^id} = input} = Actions.cast(action, %{"user_id" => id})
      refute Map.has_key?(input, :preferred_name)
    end
  end

  describe "catálogo" do
    test "los nombres son únicos y siguen la convención" do
      names = Enum.map(Actions.all(), & &1.name())
      assert names == Enum.uniq(names)
      for name <- names, do: assert(name =~ ~r/^[a-z_]+(\.[a-z_]+){2}$/)
    end

    test "cada acción tiene descripción y parámetros tipados" do
      for action <- Actions.all() do
        assert action.description() != ""

        for {field, {_type, opts}} <- action.params(),
            do: assert(is_atom(field) and is_list(opts))
      end
    end

    test "get/1 busca por nombre" do
      assert Actions.get("authorization.role_assignment.create") == AssignRole
      assert Actions.get("no.existe.nada") == nil
    end
  end

  test "emite telemetría con el nombre y el resultado", %{user: user} do
    ref = :telemetry_test.attach_event_handlers(self(), [[:amauta, :action, :stop]])

    Actions.run(
      AssignRole,
      member_scope("student"),
      assign_params(user, "teacher", "institution")
    )

    assert_received {[:amauta, :action, :stop], ^ref, _measurements,
                     %{action: "authorization.role_assignment.create", status: :forbidden}}
  end
end
