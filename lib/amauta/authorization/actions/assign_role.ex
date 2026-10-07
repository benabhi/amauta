defmodule Amauta.Authorization.Actions.AssignRole do
  @moduledoc """
  Asigna un rol a una persona en un ámbito (RF-ROL-003).

  Exige el permiso de gestión del ámbito (personas de la institución,
  matrículas del trayecto o del curso) y, por anti-escalada (RF-ROL-005),
  tener ya todos los permisos del rol en ese ámbito. Queda auditado
  (RF-ROL-011).
  """
  use Amauta.Action,
    name: "authorization.role_assignment.create",
    description: "Asigna un rol a una persona en un ámbito.",
    params: [
      user_id: {Ecto.UUID, required: true},
      role: {:string, required: true},
      scope_type: {:string, required: true},
      scope_id: Ecto.UUID
    ]

  import Ecto.Changeset

  alias Amauta.Authorization
  alias Amauta.Authorization.{RoleAssignment, Roles}

  @impl true
  def validate(changeset) do
    changeset
    |> validate_inclusion(:role, Roles.keys())
    |> validate_inclusion(:scope_type, RoleAssignment.scope_types())
  end

  @impl true
  def authorize(scope, %{role: role, scope_type: type} = input) do
    target = Authorization.target(type, input[:scope_id])

    with :ok <- Authorization.authorize(scope, Authorization.manage_permission(type), target) do
      if Authorization.can_grant?(scope, role, target), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, input) do
    Authorization.create_assignment(scope, Map.put(input, :granted_by_id, scope.user.id))
  end

  @impl true
  def after_commit(scope, _input, _assignment), do: Authorization.invalidate(scope)
end
