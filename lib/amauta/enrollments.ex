defmodule Amauta.Enrollments do
  @moduledoc """
  Matrículas y comisiones de los cursos (RF-MAT-001 a 003 y RF-COM-001 a
  003). Solo consultas y operaciones sin permisos: los cambios desde la
  interfaz pasan por `Amauta.Enrollments.Actions`.

  Cada matrícula activa se refleja en una asignación de rol ligada por
  `enrollment_id` (`sync_assignment/2`): en la comisión, si es del equipo
  docente y tiene comisión (RF-COM-002); si no, en el curso. Así los
  permisos siguen saliendo de `Amauta.Authorization`.
  """
  import Ecto.Query

  alias Amauta.Accounts.User
  alias Amauta.Authorization
  alias Amauta.Authorization.RoleAssignment
  alias Amauta.Courses.{Course, Section}
  alias Amauta.Enrollments.Enrollment
  alias Amauta.{Repo, Scope, Tenancy}

  ## Comisiones

  @doc "Comisiones del curso, por nombre."
  def list_sections(tenant, %Course{id: id}) do
    from(s in Section, where: s.course_id == ^id, order_by: s.name)
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc "Comisión por ID, con su curso, o `nil`."
  def get_section(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Section |> Repo.get(id, Tenancy.opts(tenant)) |> Repo.preload(:course)
      :error -> nil
    end
  end

  @doc "Crea una comisión. No verifica permisos."
  def create_section(tenant, %Course{} = course, attrs) do
    %Section{course_id: course.id}
    |> Section.changeset(attrs)
    |> Repo.insert(Tenancy.opts(tenant))
  end

  @doc """
  Borra una comisión: sus estudiantes quedan sin comisión y su equipo
  docente pasa al curso entero (se resincronizan sus asignaciones).
  """
  def delete_section(tenant, %Section{} = section) do
    opts = Tenancy.opts(tenant)

    affected =
      from(e in Enrollment, where: e.section_id == ^section.id)
      |> Repo.all(opts)

    with {:ok, section} <- Repo.delete(section, opts) do
      for enrollment <- affected,
          do: sync_assignment(tenant, %{enrollment | section_id: nil})

      {:ok, section}
    end
  end

  ## Consultas

  @doc """
  Matrículas del curso, con la persona y la comisión.

  Filtros: `"section"` (ID o `"none"`, sin comisión) y `"status"` (sin
  estado: todas menos las finalizadas).
  """
  def list(tenant, %Course{id: id}, filters \\ %{}) do
    Enrollment
    |> where([e], e.course_id == ^id)
    |> filter_section(filters["section"])
    |> filter_status(filters["status"])
    |> join(:inner, [e], u in assoc(e, :user))
    |> order_by([e, u], [u.last_name, u.first_name])
    |> preload([e, u], user: u)
    |> preload(:section)
    |> Repo.all(Tenancy.opts(tenant))
  end

  defp filter_section(query, value) when value in [nil, ""], do: query
  defp filter_section(query, "none"), do: where(query, [e], is_nil(e.section_id))

  defp filter_section(query, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> where(query, [e], e.section_id == ^id)
      :error -> where(query, false)
    end
  end

  defp filter_status(query, value) when value in [nil, ""],
    do: where(query, [e], e.status != "ended")

  defp filter_status(query, status), do: where(query, [e], e.status == ^status)

  @doc """
  Participantes activos, separados en `{equipo_docente, estudiantes}`. El
  equipo docente va ordenado por rol (responsable, docente, ayudante).
  """
  def participants(tenant, %Course{} = course, filters \\ %{}) do
    active = list(tenant, course, Map.put(filters, "status", "active"))
    {teaching, others} = Enum.split_with(active, &(&1.role in Enrollment.teaching_roles()))
    order = Enrollment.teaching_roles()

    {Enum.sort_by(teaching, &Enum.find_index(order, fn role -> role == &1.role end)),
     Enum.filter(others, &(&1.role == "student"))}
  end

  @doc "Matrícula por ID, con persona, comisión y curso, o `nil`."
  def get(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Enrollment
        |> Repo.get(id, Tenancy.opts(tenant))
        |> Repo.preload([:user, :section, :course])

      :error ->
        nil
    end
  end

  @doc "Matrícula de la persona en el curso, o `nil`."
  def get_by_user(tenant, %Course{id: course_id}, user_id) do
    Repo.get_by(Enrollment, [course_id: course_id, user_id: user_id], Tenancy.opts(tenant))
  end

  @doc "IDs de los cursos donde la persona tiene una matrícula activa."
  def active_course_ids(tenant, user_id) do
    from(e in Enrollment,
      where: e.user_id == ^user_id and e.status == "active",
      select: e.course_id
    )
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc """
  Indica si la persona tiene el permiso en el curso o en alguna de sus
  comisiones. Sirve para lo que un docente de comisión puede hacer «en su
  parte» del curso, como entrar o ver a sus estudiantes (RF-COM-002).
  """
  @spec can_in_course?(Scope.t(), String.t(), Course.t()) :: boolean()
  def can_in_course?(%Scope{} = scope, permission, %Course{} = course) do
    Authorization.can?(scope, permission, course) or
      Enum.any?(own_sections(scope, course), &Authorization.can?(scope, permission, &1))
  end

  @doc """
  Comisiones a las que la persona está limitada en el curso: las de su
  matrícula del equipo docente con comisión. Lista vacía: no está limitada.
  """
  def own_sections(%Scope{user: nil}, _course), do: []

  def own_sections(%Scope{user: user} = scope, %Course{} = course) do
    case get_by_user(scope, course, user.id) do
      %Enrollment{status: "active", section_id: id, role: role}
      when not is_nil(id) ->
        if role in Enrollment.teaching_roles(),
          do: [%{get_section(scope, id) | course: course}],
          else: []

      _ ->
        []
    end
  end

  ## Escritura (sin permisos)

  @doc """
  Matricula a una persona. Si ya tuvo una matrícula finalizada o
  suspendida, la reactiva con los datos nuevos; si ya está activa, es un
  error de validación.
  """
  def enroll(tenant, %Course{} = course, user_id, attrs) do
    opts = Tenancy.opts(tenant)
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end) |> Map.put("status", "active")

    result =
      case get_by_user(tenant, course, user_id) do
        nil ->
          %Enrollment{course_id: course.id, user_id: user_id}
          |> Enrollment.changeset(attrs)
          |> validate_section(tenant, course)
          |> Repo.insert(opts)

        %Enrollment{status: "active"} = existing ->
          existing
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:user_id, "already enrolled")
          |> Ecto.Changeset.apply_action(:insert)

        existing ->
          existing
          |> Enrollment.changeset(attrs)
          |> validate_section(tenant, course)
          |> Repo.update(opts)
      end

    with {:ok, enrollment} <- result do
      sync_assignment(tenant, enrollment)
      {:ok, enrollment}
    end
  end

  @doc """
  Matricula a varias personas en el curso. Las que ya están activas se
  saltean. Cada fila: `%{"user_id" => id, "role" => rol, "section_id" => id | nil}`.
  Devuelve `{:ok, %{enrolled: n, skipped: n}}` o el primer error (dentro de
  una transacción, nada queda a medias).
  """
  def enroll_many(tenant, %Course{} = course, rows, origin, enrolled_by_id) do
    Enum.reduce_while(rows, {:ok, %{enrolled: 0, skipped: 0}}, fn row, {:ok, acc} ->
      attrs = %{
        "role" => row["role"] || "student",
        "section_id" => row["section_id"],
        "origin" => origin,
        "enrolled_by_id" => enrolled_by_id
      }

      case enroll(tenant, course, row["user_id"], attrs) do
        {:ok, _} ->
          {:cont, {:ok, %{acc | enrolled: acc.enrolled + 1}}}

        {:error, %Ecto.Changeset{errors: [user_id: {"already enrolled", _}]}} ->
          {:cont, {:ok, %{acc | skipped: acc.skipped + 1}}}

        error ->
          {:halt, error}
      end
    end)
  end

  @doc "Cambia el rol, la comisión, el estado o las fechas de una matrícula."
  def update(tenant, %Enrollment{} = enrollment, attrs) do
    course = Repo.get!(Course, enrollment.course_id, Tenancy.opts(tenant))

    with {:ok, enrollment} <-
           enrollment
           |> Enrollment.changeset(attrs)
           |> validate_section(tenant, course)
           |> Repo.update(Tenancy.opts(tenant)) do
      sync_assignment(tenant, enrollment)
      {:ok, enrollment}
    end
  end

  # La comisión tiene que ser del curso.
  defp validate_section(changeset, tenant, course) do
    case Ecto.Changeset.get_field(changeset, :section_id) do
      nil ->
        changeset

      id ->
        case Repo.get(Section, id, Tenancy.opts(tenant)) do
          %Section{course_id: course_id} when course_id == course.id -> changeset
          _ -> Ecto.Changeset.add_error(changeset, :section_id, "does not belong to the course")
        end
    end
  end

  @doc """
  Rehace la asignación de rol de la matrícula: borra la anterior y, si
  está activa, crea la que corresponde. Invalida la caché de permisos.
  """
  def sync_assignment(tenant, %Enrollment{} = enrollment) do
    opts = Tenancy.opts(tenant)

    from(a in RoleAssignment, where: a.enrollment_id == ^enrollment.id)
    |> Repo.delete_all(opts)

    if enrollment.status == "active" do
      {scope_type, scope_id} =
        if enrollment.section_id && enrollment.role in Enrollment.teaching_roles(),
          do: {"section", enrollment.section_id},
          else: {"course", enrollment.course_id}

      %RoleAssignment{}
      |> RoleAssignment.changeset(%{
        user_id: enrollment.user_id,
        role: enrollment.role,
        scope_type: scope_type,
        scope_id: scope_id,
        granted_by_id: enrollment.enrolled_by_id,
        enrollment_id: enrollment.id
      })
      # Si la persona ya tenía ese mismo rol asignado a mano, se conserva.
      |> Repo.insert(Keyword.merge(opts, on_conflict: :nothing))
    end

    Authorization.invalidate(tenant)
    :ok
  end

  ## Código de inscripción

  @doc "Curso publicado con ese código y la inscripción por código habilitada, o `nil`."
  def course_for_code(tenant, code) when is_binary(code) do
    code = code |> String.trim() |> String.upcase()

    case Repo.get_by(Course, [enrollment_code: code, status: "published"], Tenancy.opts(tenant)) do
      %Course{settings: %{enrollment_code_enabled: true}} = course -> course
      _ -> nil
    end
  end

  @doc "Personas activas de la institución por email (sin distinguir mayúsculas)."
  def users_by_email(tenant, emails) do
    emails = emails |> Enum.map(&String.downcase/1) |> Enum.uniq()

    from(u in User, where: fragment("lower(?)", u.email) in ^emails)
    |> Repo.all(Tenancy.opts(tenant))
    |> Map.new(&{String.downcase(&1.email), &1})
  end
end
