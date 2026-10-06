defmodule Amauta.Authorization.Effective do
  @moduledoc """
  Permisos efectivos = unión de los permisos de las asignaciones que
  aplican al ámbito, con cascada desde la institución (RF-ROL-003 y 004).
  """
  alias Amauta.Authorization.Roles
  alias Amauta.Scope

  @doc "Permisos efectivos de la persona del scope en un curso (por ID)."
  def permissions(%Scope{user: nil}, _course_id), do: MapSet.new()

  def permissions(%Scope{assignments: assignments}, course_id) do
    assignments
    |> Enum.filter(&(is_nil(&1.course_id) or &1.course_id == course_id))
    |> Enum.flat_map(&Roles.permissions(&1.role))
    |> MapSet.new()
  end

  def allowed?(%Scope{} = scope, permission, course_id) do
    MapSet.member?(permissions(scope, course_id), permission)
  end
end
