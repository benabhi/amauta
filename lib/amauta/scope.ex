defmodule Amauta.Scope do
  @moduledoc """
  Contexto de cada acción (patrón de Phoenix 1.8): institución, persona,
  sus asignaciones de rol y metadatos de la solicitud.
  """
  alias Amauta.Authorization

  defstruct [:institution, :user, assignments: [], request: %{}]

  @type t :: %__MODULE__{}

  def for_user(institution, nil), do: %__MODULE__{institution: institution}

  def for_user(institution, user) do
    %__MODULE__{
      institution: institution,
      user: user,
      assignments: Authorization.list_assignments(institution, user.id)
    }
  end
end
