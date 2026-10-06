defmodule Amauta.Authorization.Roles do
  @moduledoc """
  Roles de sistema (RF-ROL-002, Anexo C del ERS). En el MVP solo existen
  estos; los roles personalizados llegan en V1.

  El Anexo C los describe por grupos de permisos, con marcas de «parcial»
  (lo propio, la comisión o solo lectura). Las listas de abajo son la
  traducción a permisos atómicos; los parciales se resuelven así:

    * «su comisión»: el permiso es el mismo, y el ámbito de la asignación
      (una comisión) lo limita.
    * «solo lectura»: se dan los permisos de ver y no los de modificar.

  Los permisos personales (`self.*`) los tiene toda persona sobre lo propio
  y no dependen del rol.
  """
  alias Amauta.Authorization.Permissions

  @course_base ~w(course.view course.people.view)

  @teaching ~w(
    course.people.view_contact course.content.view_hidden course.content.manage
    course.feed.post course.feed.reply course.feed.pin course.feed.moderate
    course.assignments.manage course.assessments.manage course.assessments.monitor
    course.submissions.view_all course.submissions.grade course.submissions.extend
    course.attempts.manage course.gradebook.view_all course.gradebook.edit
    course.gradebook.publish course.attendance.take course.attendance.manage
    course.messages.send_teachers course.messages.send_peers course.messages.send_selection
    course.analytics.view
  )

  @course_lead_extra ~w(
    course.update course.archive course.duplicate course.notifications.manage
    course.sections.manage course.activity.view course.certificates.issue
    course.gradebook.override_final course.gradebook.lock
  )

  @learning ~w(
    course.feed.reply course.submissions.create_own course.attempts.create_own
    course.grades.view_own course.messages.send_teachers course.messages.send_peers
  )

  @roles [
    {"institution_admin", "Administración institucional",
     Permissions.keys_with_prefix("institution.") ++
       Permissions.keys_with_prefix("pathway.") ++
       (Permissions.keys_with_prefix("course.") --
          ~w(course.submissions.create_own course.attempts.create_own course.grades.view_own))},
    {"academic_management", "Gestión académica", ~w(
       institution.users.view institution.users.manage institution.imports.manage
       institution.periods.manage institution.taxonomy.manage institution.reports.view
       pathway.view pathway.update pathway.enrollments.manage pathway.progress.view_all
       pathway.reports.view course.people.view_contact course.people.enroll
       course.sections.manage course.gradebook.view_all course.messages.send_teachers
       course.messages.send_peers course.messages.send_selection
     ) ++ @course_base},
    {"pathway_coordinator", "Coordinación de trayecto",
     ~w(institution.users.view institution.courses.create) ++
       Permissions.keys_with_prefix("pathway.") ++
       @course_base ++
       @teaching ++
       (@course_lead_extra -- ~w(course.gradebook.override_final)) ++
       ~w(course.people.enroll)},
    {"course_lead", "Docente responsable", @course_base ++ @teaching ++ @course_lead_extra},
    {"teacher", "Docente", @course_base ++ @teaching},
    {"assistant", "Ayudante",
     @course_base ++
       ~w(
         course.content.view_hidden course.feed.post course.feed.reply
         course.submissions.view_all course.submissions.grade
         course.attendance.take course.attendance.manage
         course.messages.send_teachers course.messages.send_peers course.messages.send_selection
       )},
    {"student", "Estudiante", @course_base ++ @learning},
    {"observer", "Observador",
     @course_base ++ ~w(course.gradebook.view_all course.analytics.view)}
  ]

  for {key, _name, permissions} <- @roles, permission <- permissions do
    Permissions.exists?(permission) ||
      raise CompileError, description: "role #{key}: unknown permission #{permission}"
  end

  @permissions Map.new(@roles, fn {key, _name, perms} -> {key, MapSet.new(perms)} end)
  @names Map.new(@roles, fn {key, name, _perms} -> {key, name} end)
  @keys Enum.map(@roles, &elem(&1, 0))

  @doc "Claves de los roles de sistema."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @spec exists?(String.t()) :: boolean()
  def exists?(key), do: Map.has_key?(@permissions, key)

  @doc "Nombre del rol para mostrar."
  @spec name(String.t()) :: String.t()
  def name(key), do: Map.fetch!(@names, key)

  @doc "Permisos del rol."
  @spec permissions(String.t()) :: MapSet.t(String.t())
  def permissions(key), do: Map.fetch!(@permissions, key)
end
