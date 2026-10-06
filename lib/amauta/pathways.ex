defmodule Amauta.Pathways do
  @moduledoc """
  Trayectos y sus etapas (RF-TRA-001 y RF-TRA-002). Solo consultas y
  operaciones sin permisos: los cambios desde la interfaz pasan por
  `Amauta.Pathways.Actions`.

  Los responsables de un trayecto son las personas con el rol
  `pathway_coordinator` en su ámbito; se asignan con las acciones de
  `Amauta.Authorization.Actions`.
  """
  import Ecto.Query

  alias Amauta.Accounts.User
  alias Amauta.Authorization
  alias Amauta.Authorization.{RoleAssignment, Roles}
  alias Amauta.Pathways.{Pathway, Stage}
  alias Amauta.{Repo, Scope, Slug, Tenancy}

  @coordinator_role "pathway_coordinator"

  @doc "Rol de quienes son responsables de un trayecto."
  def coordinator_role, do: @coordinator_role

  ## Consultas

  @doc """
  Trayectos que la persona del scope puede ver: todos, si tiene
  `pathway.view` en la institución; si no, solo aquellos donde tiene un rol
  que lo incluye.

  Filtros: `"q"` (nombre o código) y `"status"`. Sin estado, se muestran
  los que no están archivados.
  """
  @spec list_visible(Scope.t(), map()) :: [Pathway.t()]
  def list_visible(%Scope{} = scope, filters \\ %{}) do
    Pathway
    |> filter_visible(scope)
    |> filter_q(filters["q"])
    |> filter_status(filters["status"])
    |> order_by([p], [p.name, p.id])
    |> Repo.all(Tenancy.opts(scope))
  end

  defp filter_visible(query, scope) do
    if Authorization.can?(scope, "pathway.view") do
      query
    else
      ids = visible_ids(scope)
      where(query, [p], p.id in ^ids)
    end
  end

  defp visible_ids(%Scope{user: nil}), do: []

  defp visible_ids(scope) do
    scope
    |> Authorization.list_assignments(scope.user.id)
    |> Enum.filter(
      &(&1.scope_type == "pathway" and MapSet.member?(Roles.permissions(&1.role), "pathway.view"))
    )
    |> Enum.map(& &1.scope_id)
  end

  defp filter_q(query, q) when q in [nil, ""], do: query

  defp filter_q(query, q) do
    pattern = "%" <> String.replace(String.downcase(q), ~w(\\ % _), &("\\" <> &1)) <> "%"
    where(query, [p], ilike(p.name, ^pattern) or ilike(p.code, ^pattern))
  end

  defp filter_status(query, status) when status in [nil, ""],
    do: where(query, [p], p.status != "archived")

  defp filter_status(query, status), do: where(query, [p], p.status == ^status)

  @doc "Trayecto por slug, con sus etapas, o `nil`."
  def get_by_slug(tenant, slug) when is_binary(slug) do
    Pathway
    |> Repo.get_by([slug: slug], Tenancy.opts(tenant))
    |> Repo.preload(:stages)
  end

  @doc "Trayecto por ID, o `nil`."
  def get(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Pathway, id, Tenancy.opts(tenant))
      :error -> nil
    end
  end

  @doc "Etapa por ID, con su trayecto, o `nil`."
  def get_stage(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Stage |> Repo.get(id, Tenancy.opts(tenant)) |> Repo.preload(:pathway)
      :error -> nil
    end
  end

  @doc "Etapas del trayecto, en orden."
  def list_stages(tenant, %Pathway{id: id}) do
    from(s in Stage, where: s.pathway_id == ^id, order_by: s.position)
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc "Responsables del trayecto, con el ID de su asignación."
  @spec coordinators(Tenancy.tenant(), Pathway.t()) :: [{User.t(), Ecto.UUID.t()}]
  def coordinators(tenant, %Pathway{id: id}) do
    from(a in RoleAssignment,
      join: u in User,
      on: u.id == a.user_id,
      where: a.scope_type == "pathway" and a.scope_id == ^id and a.role == @coordinator_role,
      order_by: [u.last_name, u.first_name],
      select: {u, a.id}
    )
    |> Repo.all(Tenancy.opts(tenant))
  end

  ## Escritura (sin permisos)

  @doc """
  Crea un trayecto. Sin slug, lo deriva del nombre y, si ya está en uso, le
  agrega un número (`sistemas-2`).
  """
  def create(tenant, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    attrs =
      if blank?(attrs["slug"]),
        do: Map.put(attrs, "slug", Slug.available(tenant, Pathway, Slug.slugify(attrs["name"]))),
        else: attrs

    %Pathway{}
    |> Pathway.changeset(attrs)
    |> Repo.insert(Tenancy.opts(tenant))
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""

  @doc "Agrega una etapa al final del trayecto."
  def add_stage(tenant, %Pathway{id: pathway_id}, attrs) do
    opts = Tenancy.opts(tenant)

    last =
      from(s in Stage, where: s.pathway_id == ^pathway_id, select: max(s.position))
      |> Repo.one(opts)

    %Stage{pathway_id: pathway_id, position: (last || 0) + 1}
    |> Stage.changeset(attrs)
    |> Repo.insert(opts)
  end

  @doc """
  Mueve una etapa un lugar hacia arriba (`:up`) o hacia abajo (`:down`).
  En los extremos no hace nada. Debe correr dentro de una transacción: la
  unicidad de las posiciones se verifica al confirmar.
  """
  def move_stage(tenant, %Stage{} = stage, direction) when direction in [:up, :down] do
    opts = Tenancy.opts(tenant)
    target = if direction == :up, do: stage.position - 1, else: stage.position + 1

    case Repo.get_by(Stage, [pathway_id: stage.pathway_id, position: target], opts) do
      nil ->
        {:ok, stage}

      neighbor ->
        Repo.update!(Ecto.Changeset.change(neighbor, position: stage.position), opts)
        Repo.update(Ecto.Changeset.change(stage, position: target), opts)
    end
  end

  @doc "Borra una etapa y corre las siguientes un lugar hacia arriba."
  def delete_stage(tenant, %Stage{} = stage) do
    opts = Tenancy.opts(tenant)

    with {:ok, stage} <- Repo.delete(stage, opts) do
      from(s in Stage,
        where: s.pathway_id == ^stage.pathway_id and s.position > ^stage.position
      )
      |> Repo.update_all([inc: [position: -1]], opts)

      {:ok, stage}
    end
  end
end
