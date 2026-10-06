defmodule Amauta.Authorization do
  @moduledoc """
  Permisos efectivos (sección 5.17 del ERS).

  Permisos efectivos de una persona sobre un objetivo = unión de los
  permisos de los roles de todas sus asignaciones que aplican: las de la
  institución y las de cualquier ámbito que contenga al objetivo (cascada,
  RF-ROL-003 y RF-ROL-004). Una asignación en una comisión limita sus
  permisos de curso a esa comisión.

  Se verifica siempre en el servidor (RF-ROL-012): las acciones llaman a
  `authorize/3` antes de ejecutar.
  """
  import Ecto.Query

  alias Amauta.Authorization.{Cache, Permissions, RoleAssignment, Roles, ScopeRef, Target}
  alias Amauta.{Repo, Scope, Tenancy}

  @type target :: :institution | Target.t()

  ## Asignaciones

  @doc "Asignaciones de una persona."
  def list_assignments(tenant, user_id) do
    from(a in RoleAssignment, where: a.user_id == ^user_id, order_by: a.inserted_at)
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc """
  Crea una asignación. No verifica permisos: para eso está la acción
  `Amauta.Authorization.Actions.AssignRole`.
  """
  def create_assignment(tenant, attrs) do
    result =
      %RoleAssignment{}
      |> RoleAssignment.changeset(attrs)
      |> Repo.insert(Tenancy.opts(tenant))

    invalidate(tenant)
    result
  end

  @doc "Asignación por ID, o `nil`."
  def get_assignment(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(RoleAssignment, id, Tenancy.opts(tenant))
      :error -> nil
    end
  end

  @doc "Borra una asignación."
  def delete_assignment(tenant, %RoleAssignment{} = assignment) do
    result = Repo.delete(assignment, Tenancy.opts(tenant))
    invalidate(tenant)
    result
  end

  @doc "Invalida la caché de permisos de la institución."
  def invalidate(tenant), do: Cache.invalidate(institution_id(tenant))

  ## Permisos efectivos

  @doc "Permisos efectivos de la persona del scope sobre el objetivo."
  @spec permissions(Scope.t(), target()) :: MapSet.t(String.t())
  def permissions(scope, target \\ :institution)

  def permissions(%Scope{user: nil}, _target), do: MapSet.new()

  def permissions(%Scope{} = scope, target) do
    applicable = MapSet.new([{"institution", nil} | chain(target)])

    scope
    |> cached_assignments()
    |> Enum.filter(&MapSet.member?(applicable, {&1.scope_type, &1.scope_id}))
    |> Enum.reduce(MapSet.new(), &MapSet.union(&2, Roles.permissions(&1.role)))
  end

  @doc """
  Indica si la persona tiene el permiso sobre el objetivo. Falla si el
  permiso no existe en el catálogo, para no ocultar errores de tipeo.
  """
  @spec can?(Scope.t(), String.t(), target()) :: boolean()
  def can?(%Scope{} = scope, permission, target \\ :institution) do
    Permissions.fetch!(permission)
    MapSet.member?(permissions(scope, target), permission)
  end

  @doc "`:ok` si la persona tiene el permiso; si no, `{:error, :forbidden}`."
  @spec authorize(Scope.t(), String.t(), target()) :: :ok | {:error, :forbidden}
  def authorize(%Scope{} = scope, permission, target \\ :institution) do
    if can?(scope, permission, target), do: :ok, else: {:error, :forbidden}
  end

  @doc """
  Anti-escalada (RF-ROL-005): solo se puede asignar un rol cuyos permisos
  la persona ya tiene en ese ámbito.

  Solo cuentan los permisos de riesgo medio y alto (Anexo B). Los de riesgo
  bajo son de participación (ver, responder, entregar lo propio) y no dan
  poder sobre otras personas; sin esta excepción, ni la docencia ni la
  gestión académica podrían matricular estudiantes. Ver ADR-0006.
  """
  @spec can_grant?(Scope.t(), String.t(), target()) :: boolean()
  def can_grant?(%Scope{} = scope, role, target) do
    Roles.exists?(role) and
      MapSet.subset?(grantable(Roles.permissions(role)), permissions(scope, target))
  end

  defp grantable(permissions) do
    MapSet.reject(permissions, &(Permissions.fetch!(&1).risk == :low))
  end

  @doc """
  Objetivo de un ámbito por tipo e ID. En H0 los trayectos, cursos y
  comisiones todavía no tienen tabla: se resuelven sin ámbitos contenedores.
  Cuando existan, esta función carga la entidad y su cadena.
  """
  @spec target(String.t(), Ecto.UUID.t() | nil) :: target()
  def target("institution", _id), do: :institution
  def target(type, id) when type in ~w(pathway course section), do: %ScopeRef{type: type, id: id}

  @doc "Permiso que gestiona las asignaciones de un tipo de ámbito."
  @spec manage_permission(String.t()) :: String.t()
  def manage_permission("institution"), do: "institution.users.manage"
  def manage_permission("pathway"), do: "pathway.enrollments.manage"
  def manage_permission(type) when type in ~w(course section), do: "course.people.enroll"

  defp chain(:institution), do: []
  defp chain(target), do: Target.scope_chain(target)

  defp cached_assignments(%Scope{institution: institution, user: user} = scope) do
    Cache.fetch(institution.id, user.id, fn -> list_assignments(scope, user.id) end)
  end

  defp institution_id(tenant), do: tenant |> to_institution() |> Map.fetch!(:id)

  defp to_institution(%Amauta.Platform.Institution{} = institution), do: institution
  defp to_institution(%{institution: institution}), do: institution
end
