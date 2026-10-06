defmodule Amauta.Authorization do
  @moduledoc """
  Permisos efectivos = unión de los permisos de las asignaciones que
  aplican al ámbito, con cascada desde la institución (RF-ROL-003 y 004).
  """
  import Ecto.Query
  alias Amauta.Authorization.{RoleAssignment, Roles}
  alias Amauta.Catalog.Course
  alias Amauta.{Repo, Scope, Tenancy}

  def assign_role(tenant, attrs) do
    %RoleAssignment{} |> RoleAssignment.changeset(attrs) |> Repo.insert(Tenancy.opts(tenant))
  end

  def list_assignments(tenant, user_id) do
    Repo.all(from(a in RoleAssignment, where: a.user_id == ^user_id), Tenancy.opts(tenant))
  end

  @doc "Permisos efectivos de la persona del scope en un curso."
  def permissions(%Scope{user: nil}, _course), do: MapSet.new()

  def permissions(%Scope{assignments: assignments}, %Course{id: course_id}) do
    assignments
    |> Enum.filter(&(is_nil(&1.course_id) or &1.course_id == course_id))
    |> Enum.flat_map(&Roles.permissions(&1.role))
    |> MapSet.new()
  end

  def can?(%Scope{} = scope, permission, %Course{} = course) do
    MapSet.member?(permissions(scope, course), permission)
  end
end
