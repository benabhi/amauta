defmodule Amauta.Scope do
  @moduledoc """
  Contexto de cada acción (patrón de Phoenix 1.8): institución, persona,
  sus asignaciones de rol y metadatos de la solicitud. Se pasa a Ash como
  `scope:`; Ash obtiene de acá el actor y la institución (tenant).
  """
  alias Amauta.Authorization

  defstruct [:institution, :user, assignments: [], request: %{}]

  @type t :: %__MODULE__{}

  def for_user(institution, nil), do: %__MODULE__{institution: institution}

  def for_user(institution, user) do
    %__MODULE__{
      institution: institution,
      user: user,
      assignments:
        Authorization.list_assignments!(user.id, tenant: institution, authorize?: false)
    }
  end

  defimpl Ash.Scope.ToOpts do
    # El actor es el Scope completo: las políticas necesitan las asignaciones.
    def get_actor(%{user: nil}), do: {:ok, nil}
    def get_actor(scope), do: {:ok, scope}
    def get_tenant(%{institution: institution}), do: {:ok, institution}
    def get_context(_), do: :error
    def get_tracer(_), do: :error
    def get_authorize?(_), do: :error
  end
end
