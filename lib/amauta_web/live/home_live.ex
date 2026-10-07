defmodule AmautaWeb.HomeLive do
  @moduledoc """
  Inicio adaptado al rol (RF-INS-002 y RF-UI-001):

    * La administración ve indicadores de la institución y sus pendientes
      de gestión (invitaciones sin aceptar, cursos en borrador, cursos sin
      equipo docente y estudiantes sin comisión).
    * Docentes y estudiantes ven sus cursos. «Para revisar» (docencia) y
      «Para hoy y esta semana» (estudiantes) muestran su estado vacío hasta
      que existan tareas y entregas (H3).
  """
  use AmautaWeb, :live_view

  alias Amauta.Accounts.User
  alias Amauta.Enrollments.Enrollment
  alias Amauta.Home
  alias AmautaWeb.{CourseLive, Format, Paths}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    courses = Home.my_courses(scope)
    manager = Home.manager?(scope)
    roles = MapSet.new(courses, &elem(&1, 1))

    {:ok,
     assign(socket,
       page_title: gettext("Home"),
       courses: courses,
       manager: manager,
       stats: manager && Home.stats(scope),
       pending: if(manager, do: Home.pending(scope), else: []),
       teaching: Enum.any?(Enrollment.teaching_roles(), &MapSet.member?(roles, &1)),
       learning: MapSet.member?(roles, "student")
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:home}>
      <.header>
        {gettext("Hello, %{name}", name: User.given_name(@current_scope.user))}
        <:subtitle>{@current_scope.institution.name}</:subtitle>
        <:actions>
          <.button variant="secondary" icon="key" navigate={Paths.join(@current_scope)}>
            {gettext("Join with a code")}
          </.button>
        </:actions>
      </.header>
      <p id="current-user" class="sr-only">{User.display_name(@current_scope.user)}</p>

      <section :if={@manager} id="institution-overview" class="mb-10" aria-labelledby="overview-title">
        <h2 id="overview-title" class="mb-3 font-display text-lg font-semibold">
          {gettext_term(@current_scope, :institution, "Your %{term} today")}
        </h2>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.stat
            id="stat-people"
            value={Format.number(@stats.active_people)}
            label={gettext("Active people")}
            icon="users"
            navigate={Paths.people(@current_scope)}
          >
            <:detail :if={@stats.invited_people > 0}>
              {ngettext(
                "%{count} with a pending invitation",
                "%{count} with a pending invitation",
                @stats.invited_people
              )}
            </:detail>
          </.stat>
          <.stat
            id="stat-courses"
            value={Format.number(@stats.published_courses)}
            label={gettext_term(@current_scope, :course, "Published %{terms}")}
            icon="book-open"
            family="airampo"
            navigate={Paths.courses(@current_scope)}
          >
            <:detail :if={@stats.draft_courses > 0}>
              {ngettext("%{count} draft", "%{count} drafts", @stats.draft_courses)}
            </:detail>
          </.stat>
          <.stat
            id="stat-pathways"
            value={Format.number(@stats.published_pathways)}
            label={gettext_term(@current_scope, :pathway, "Published %{terms}")}
            icon="path"
            family="chilca"
            navigate={Paths.pathways(@current_scope)}
          />
          <.stat
            id="stat-enrollments"
            value={Format.number(@stats.active_enrollments)}
            label={gettext("Active enrollments")}
            icon="graduation-cap"
            family="qolle"
          />
        </div>

        <.card :if={@pending != []} id="pending" class="mt-4">
          <:header>{gettext("Pending")}</:header>
          <ul class="divide-y divide-line">
            <li :for={{kind, count} <- @pending} id={"pending-#{kind}"} class="py-2">
              <.link
                navigate={pending_path(@current_scope, kind)}
                class="flex items-center justify-between gap-3 hover:text-primary"
              >
                <span>{pending_label(@current_scope, kind, count)}</span>
                <.icon name="caret-right" class="size-4 text-ink-muted" />
              </.link>
            </li>
          </ul>
        </.card>
      </section>

      <section id="my-courses" aria-labelledby="my-courses-title">
        <h2 id="my-courses-title" class="mb-3 font-display text-lg font-semibold">
          {gettext_term(@current_scope, :course, "My %{terms}")}
        </h2>

        <.empty_state
          :if={@courses == []}
          icon="book-open"
          title={gettext_term(@current_scope, :course, "You have no %{terms} yet")}
        >
          {gettext("When you join a class, you will find it here.")}
        </.empty_state>

        <ul :if={@courses != []} class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <li :for={{course, role} <- @courses} id={"my-course-#{course.id}"}>
            <.tile
              navigate={Paths.course(@current_scope, course)}
              icon={course.icon}
              family={course.color}
              title={course.name}
            >
              <:subtitle>{course.period && course.period.name}</:subtitle>
              <:badge>
                <.badge :if={role != "student"} family="anil">
                  {Amauta.Authorization.Roles.name(role)}
                </.badge>
                <CourseLive.status_badge
                  :if={course.status != "published"}
                  status={course.status}
                  current_scope={@current_scope}
                />
              </:badge>
            </.tile>
          </li>
        </ul>
      </section>

      <div :if={@teaching or @learning} class="mt-10 grid gap-6 lg:grid-cols-2">
        <.card :if={@teaching} id="to-review">
          <:header>{gettext("To review")}</:header>
          <p class="text-ink-muted">
            {gettext("Submissions waiting for feedback will appear here.")}
          </p>
        </.card>
        <.card :if={@learning} id="to-do">
          <:header>{gettext("For today and this week")}</:header>
          <p class="text-ink-muted">
            {gettext("Your upcoming assignments and assessments will appear here.")}
          </p>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  defp pending_path(scope, :invitations), do: Paths.people(scope, %{"status" => "invited"})
  defp pending_path(scope, :drafts), do: Paths.courses(scope, %{"status" => "draft"})
  defp pending_path(scope, _kind), do: Paths.courses(scope)

  defp pending_label(_scope, :invitations, count),
    do:
      ngettext(
        "%{count} invitation not accepted yet",
        "%{count} invitations not accepted yet",
        count
      )

  defp pending_label(scope, :drafts, count),
    do: gettext("In draft: %{count} %{what}", count: count, what: term(scope, :course, count))

  defp pending_label(scope, :without_teachers, count) do
    gettext("Without a teaching team: %{count} %{what}",
      count: count,
      what: term(scope, :course, count)
    )
  end

  defp pending_label(scope, :without_section, count) do
    ngettext(
      "Without %{section}: %{count} student",
      "Without %{section}: %{count} students",
      count,
      section: term(scope, :section)
    )
  end
end
