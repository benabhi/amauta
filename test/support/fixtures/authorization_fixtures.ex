defmodule Amauta.AuthorizationFixtures do
  @moduledoc "Asignaciones de rol de prueba, sobre la institución del test."
  import Amauta.AccountsFixtures

  alias Amauta.{Authorization, Scope}

  @doc """
  Crea una persona con el rol dado y devuelve su scope. Sin ámbito, el rol
  es de toda la institución; si no, `{tipo, id}`.
  """
  def member_scope(role, scope \\ :institution) do
    user = user_fixture()
    assign!(user, role, scope)
    Scope.for_user(institution(), user)
  end

  def assign!(user, role, :institution), do: assign!(user, role, {"institution", nil})

  def assign!(user, role, {type, id}) do
    {:ok, assignment} =
      Authorization.create_assignment(institution(), %{
        user_id: user.id,
        role: role,
        scope_type: type,
        scope_id: id
      })

    assignment
  end
end
