defmodule Amauta.Courses do
  @moduledoc """
  Cursos de la institución (RF-CUR-001, RF-CUR-005 y RF-CUR-007). Solo
  consultas y operaciones sin permisos: los cambios desde la interfaz pasan
  por `Amauta.Courses.Actions`.

  Quiénes participan de un curso salen de sus matrículas
  (`Amauta.Enrollments`).
  """
  import Ecto.Query

  alias Amauta.Authorization
  alias Amauta.Authorization.Roles
  alias Amauta.Courses.Course
  alias Amauta.Pathways.{Pathway, Stage}
  alias Amauta.{Periods, Repo, Scope, Slug, Tenancy}

  ## Consultas

  @doc """
  Cursos que la persona del scope puede ver: todos, si tiene `course.view`
  en la institución; si no, los de los cursos y trayectos donde tiene un
  rol que lo incluye.

  Filtros: `"q"` (nombre o código), `"status"` (sin estado, los no
  archivados), `"period_id"` y `"pathway_id"`.
  """
  @spec list_visible(Scope.t(), map()) :: [Course.t()]
  def list_visible(%Scope{} = scope, filters \\ %{}) do
    Course
    |> filter_visible(scope)
    |> filter_q(filters["q"])
    |> filter_status(filters["status"])
    |> filter_by(:period_id, filters["period_id"])
    |> filter_by(:pathway_id, filters["pathway_id"])
    |> order_by([c], [c.name, c.id])
    |> preload(:period)
    |> Repo.all(Tenancy.opts(scope))
  end

  defp filter_visible(query, scope) do
    if Authorization.can?(scope, "course.view") do
      query
    else
      {courses, pathways} = visible_scopes(scope)
      where(query, [c], c.id in ^courses or c.pathway_id in ^pathways)
    end
  end

  defp visible_scopes(%Scope{user: nil}), do: {[], []}

  defp visible_scopes(scope) do
    assignments =
      scope
      |> Authorization.list_assignments(scope.user.id)
      |> Enum.filter(&MapSet.member?(Roles.permissions(&1.role), "course.view"))

    ids = fn type -> for a <- assignments, a.scope_type == type, do: a.scope_id end

    # Las matrículas activas incluyen a los docentes de comisión, cuya
    # asignación es en la comisión y no en el curso.
    courses =
      Enum.uniq(ids.("course") ++ Amauta.Enrollments.active_course_ids(scope, scope.user.id))

    {courses, ids.("pathway")}
  end

  defp filter_q(query, q) when q in [nil, ""], do: query

  defp filter_q(query, q) do
    pattern = "%" <> String.replace(String.downcase(q), ~w(\\ % _), &("\\" <> &1)) <> "%"
    where(query, [c], ilike(c.name, ^pattern) or ilike(c.code, ^pattern))
  end

  defp filter_status(query, status) when status in [nil, ""],
    do: where(query, [c], c.status != "archived")

  defp filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp filter_by(query, _field, value) when value in [nil, ""], do: query

  defp filter_by(query, field, value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> where(query, [c], field(c, ^field) == ^id)
      :error -> where(query, false)
    end
  end

  @doc "Curso por slug, con período, trayecto y etapa, o `nil`."
  def get_by_slug(tenant, slug) when is_binary(slug) do
    Course
    |> Repo.get_by([slug: slug], Tenancy.opts(tenant))
    |> Repo.preload([:period, :pathway, :stage])
  end

  @doc "Curso por ID, o `nil`."
  def get(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Course, id, Tenancy.opts(tenant))
      :error -> nil
    end
  end

  @doc "Cursos de un trayecto, agrupados por ID de etapa (`nil`: sin etapa)."
  @spec by_stage(Tenancy.tenant(), Pathway.t()) :: %{(Ecto.UUID.t() | nil) => [Course.t()]}
  def by_stage(tenant, %Pathway{id: id}) do
    from(c in Course,
      where: c.pathway_id == ^id and c.status != "archived",
      order_by: [desc: c.required, asc: c.name]
    )
    |> Repo.all(Tenancy.opts(tenant))
    |> Enum.group_by(& &1.stage_id)
  end

  ## Escritura (sin permisos)

  @doc """
  Crea un curso. Sin slug, lo deriva del nombre; sin período, usa el
  actual; siempre genera un código de inscripción.
  """
  def create(tenant, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    opts = Tenancy.opts(tenant)

    attrs =
      attrs
      |> put_default("slug", fn -> Slug.available(tenant, Course, Slug.slugify(attrs["name"])) end)
      |> put_default("period_id", fn -> with %{id: id} <- Periods.current(tenant), do: id end)

    %Course{enrollment_code: new_enrollment_code(tenant)}
    |> Course.changeset(attrs)
    |> validate_stage(tenant)
    |> Repo.insert(opts)
  end

  @doc "Actualiza los datos del curso."
  def update(tenant, %Course{} = course, attrs) do
    course
    |> Course.changeset(attrs)
    |> validate_stage(tenant)
    |> Repo.update(Tenancy.opts(tenant))
  end

  @doc "Genera un código de inscripción nuevo para el curso."
  def regenerate_enrollment_code(tenant, %Course{} = course) do
    course
    |> Ecto.Changeset.change(enrollment_code: new_enrollment_code(tenant))
    |> Repo.update(Tenancy.opts(tenant))
  end

  # La etapa tiene que ser del trayecto del curso.
  defp validate_stage(changeset, tenant) do
    stage_id = Ecto.Changeset.get_field(changeset, :stage_id)
    pathway_id = Ecto.Changeset.get_field(changeset, :pathway_id)

    with id when not is_nil(id) <- stage_id,
         %Stage{pathway_id: ^pathway_id} <- Repo.get(Stage, id, Tenancy.opts(tenant)) do
      changeset
    else
      nil -> changeset
      _ -> Ecto.Changeset.add_error(changeset, :stage_id, "does not belong to the pathway")
    end
  end

  defp put_default(attrs, key, fun) do
    if blank?(attrs[key]), do: Map.put(attrs, key, fun.()), else: attrs
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""

  # Sin caracteres ambiguos (0/O, 1/I/L), para dictarlo en voz alta.
  @alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"

  defp new_enrollment_code(tenant) do
    code = for _ <- 1..7, into: "", do: <<Enum.random(@alphabet)>>

    if Repo.exists?(from(c in Course, where: c.enrollment_code == ^code), Tenancy.opts(tenant)),
      do: new_enrollment_code(tenant),
      else: code
  end
end
