defmodule Amauta.Home do
  @moduledoc """
  Datos del inicio adaptado al rol (RF-INS-002 y RF-UI-001): los cursos de
  la persona y, para la administración, indicadores y pendientes de
  gestión. Solo consultas.

  «Para hoy», «Esta semana» y «Para revisar» dependen de tareas y entregas
  (H3); por ahora el inicio muestra sus estados vacíos.
  """
  import Ecto.Query

  alias Amauta.Accounts.User
  alias Amauta.Courses.Course
  alias Amauta.Enrollments.Enrollment
  alias Amauta.Pathways.Pathway
  alias Amauta.{Authorization, Repo, Scope, Tenancy}

  @doc """
  Cursos de la persona: los de sus matrículas activas, con su rol. Los
  borradores solo aparecen si puede editarlos (docencia que los prepara).
  Devuelve `[{curso, rol}]`, por nombre.
  """
  @spec my_courses(Scope.t()) :: [{Course.t(), String.t()}]
  def my_courses(%Scope{user: user} = scope) do
    opts = Tenancy.opts(scope)

    rows =
      from(e in Enrollment,
        join: c in assoc(e, :course),
        where: e.user_id == ^user.id and e.status == "active" and c.status != "archived",
        order_by: c.name,
        select: {c, e.role}
      )
      |> Repo.all(opts)

    courses = rows |> Enum.map(&elem(&1, 0)) |> Repo.preload(:period, opts)

    Enum.zip(courses, Enum.map(rows, &elem(&1, 1)))
    |> Enum.filter(fn {course, _role} ->
      course.status == "published" or Authorization.can?(scope, "course.update", course)
    end)
  end

  @doc "Si el inicio muestra el panel de gestión: quien ve el directorio o los reportes."
  @spec manager?(Scope.t()) :: boolean()
  def manager?(scope) do
    Authorization.can?(scope, "institution.users.view") or
      Authorization.can?(scope, "institution.reports.view")
  end

  @doc """
  Indicadores de la institución: personas activas e invitadas, cursos
  publicados y en borrador, trayectos publicados y matrículas activas.
  """
  def stats(tenant) do
    opts = Tenancy.opts(tenant)
    count = fn query -> Repo.aggregate(query, :count, opts) end

    %{
      active_people: count.(from(u in User, where: u.status == "active")),
      invited_people: count.(from(u in User, where: u.status == "invited")),
      published_courses: count.(from(c in Course, where: c.status == "published")),
      draft_courses: count.(from(c in Course, where: c.status == "draft")),
      published_pathways: count.(from(p in Pathway, where: p.status == "published")),
      active_enrollments: count.(from(e in Enrollment, where: e.status == "active"))
    }
  end

  @doc """
  Pendientes de gestión, cada uno con su cantidad (solo los que hay):

    * `:invitations`: invitaciones sin aceptar.
    * `:drafts`: cursos en borrador.
    * `:without_teachers`: cursos publicados sin equipo docente.
    * `:without_section`: estudiantes sin comisión en cursos que tienen
      comisiones.
  """
  def pending(tenant) do
    opts = Tenancy.opts(tenant)
    count = fn query -> Repo.aggregate(query, :count, opts) end
    teaching = Enrollment.teaching_roles()

    with_teachers =
      from(e in Enrollment,
        where: e.status == "active" and e.role in ^teaching,
        select: e.course_id
      )

    with_sections = from(s in Amauta.Courses.Section, select: s.course_id)

    [
      invitations: count.(from(u in User, where: u.status == "invited")),
      drafts: count.(from(c in Course, where: c.status == "draft")),
      without_teachers:
        count.(
          from(c in Course,
            where: c.status == "published" and c.id not in subquery(with_teachers)
          )
        ),
      without_section:
        count.(
          from(e in Enrollment,
            where:
              e.status == "active" and e.role == "student" and is_nil(e.section_id) and
                e.course_id in subquery(with_sections)
          )
        )
    ]
    |> Enum.filter(fn {_key, n} -> n > 0 end)
  end
end
