defmodule Amauta.Authorization.Actions.RevokeRole do
  @moduledoc """
  Quita una asignación de rol. Exige lo mismo que asignarla: no se puede
  quitar un rol que uno mismo no podría dar (RF-ROL-005). Queda auditado.
  """
  use Amauta.Action,
    name: "authorization.role_assignment.delete",
    description: "Quita una asignación de rol.",
    params: [assignment_id: {Ecto.UUID, required: true}]

  alias Amauta.Authorization

  @impl true
  def authorize(scope, %{assignment_id: id}) do
    case Authorization.get_assignment(scope, id) do
      nil ->
        {:error, :not_found}

      assignment ->
        target = Authorization.target(assignment.scope_type, assignment.scope_id)
        permission = Authorization.manage_permission(assignment.scope_type)

        with :ok <- Authorization.authorize(scope, permission, target) do
          if Authorization.can_grant?(scope, assignment.role, target),
            do: :ok,
            else: {:error, :forbidden}
        end
    end
  end

  @impl true
  def run(scope, %{assignment_id: id}) do
    case Authorization.get_assignment(scope, id) do
      nil -> {:error, :not_found}
      assignment -> Authorization.delete_assignment(scope, assignment)
    end
  end

  @impl true
  def after_commit(scope, _input, _assignment), do: Authorization.invalidate(scope)
end
