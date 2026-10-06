defmodule Amauta.Authorization.Checks.CoursePermissionFilter do
  @moduledoc """
  Política de filtro: en las lecturas, el actor solo ve las filas de los
  cursos donde tiene el permiso. Con el permiso a nivel institución, ve todo.
  """
  use Ash.Policy.FilterCheck

  alias Amauta.Authorization.Roles

  @impl true
  def describe(opts), do: "rows of courses where the actor has #{opts[:permission]}"

  @impl true
  def filter(%Amauta.Scope{assignments: assignments}, _context, opts) do
    granting = Enum.filter(assignments, &(opts[:permission] in Roles.permissions(&1.role)))

    if Enum.any?(granting, &is_nil(&1.course_id)) do
      true
    else
      course_ids = Enum.map(granting, & &1.course_id)
      expr(course_id in ^course_ids)
    end
  end

  def filter(_actor, _context, _opts), do: false
end
