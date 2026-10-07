defmodule AmautaWeb.CourseLive do
  @moduledoc """
  Interior de un curso (ERS 4.3): encabezado con portada, período, equipo
  docente y código de inscripción (RF-CUR-003), y las pestañas fijas
  Tablón, Contenido, Personas y Calificaciones (RF-CUR-002), más Ajustes
  para quienes pueden editarlo (RF-CUR-005 y RF-CUR-007).

  Ver exige `course.view` sobre el curso; un borrador, además,
  `course.update`. Cada cambio pasa por su acción, que vuelve a verificar
  el permiso. Un curso archivado es de solo lectura hasta que se reabre.

  El tablón, el contenido y las calificaciones llegan en H2 y H3: por ahora
  muestran su estado vacío.
  """
  use AmautaWeb, :live_view

  alias Amauta.Accounts.{Directory, User}
  alias Amauta.{Actions, Authorization, Courses, Enrollments, Pathways, Periods}
  alias Amauta.Authorization.Roles

  alias Amauta.Courses.Actions.{
    ArchiveCourse,
    PublishCourse,
    RegenerateEnrollmentCode,
    ReopenCourse,
    UpdateCourse,
    UpdateCourseSettings
  }

  alias Amauta.Courses.{Course, Settings}

  alias Amauta.Enrollments.Actions.{
    CreateSection,
    DeleteSection,
    EndEnrollment,
    EnrollUser,
    UpdateEnrollment,
    UpdateSection
  }

  alias Amauta.Enrollments.Enrollment
  alias AmautaWeb.Paths

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    course = Courses.get_by_slug(scope, slug) || raise AmautaWeb.NotFoundError

    unless Enrollments.can_in_course?(scope, "course.view", course) and
             (course.status != "draft" or Authorization.can?(scope, "course.update", course)) do
      raise AmautaWeb.ForbiddenError
    end

    {:ok,
     socket
     |> assign(page_title: course.name, form: nil, settings_form: nil)
     |> assign(periods: [], pathways: [], stages: [], standalone: true)
     |> assign(section_filter: nil, section_form: nil, editing_section: nil)
     |> assign(people_query: "", people_results: [], enroll_form: enroll_form())
     |> assign_course(course)}
  end

  defp assign_course(socket, course) do
    scope = socket.assigns.current_scope
    can = &Authorization.can?(scope, &1, course)
    open = course.status != "archived"
    {teaching, _students} = Enrollments.participants(scope, course)
    sections = Enrollments.list_sections(scope, course)

    assign(socket,
      course: course,
      teaching: teaching,
      sections: sections,
      own_section_ids: scope |> Enrollments.own_sections(course) |> Enum.map(& &1.id),
      can_enroll: open and can.("course.people.enroll"),
      can_manage_sections: open and can.("course.sections.manage"),
      can_update: open and can.("course.update"),
      can_archive: can.("course.archive"),
      can_settings: can.("course.update") or can.("course.archive"),
      can_see_code: can.("course.people.enroll") or can.("course.update")
    )
  end

  defp reload(socket) do
    course = Courses.get_by_slug(socket.assigns.current_scope, socket.assigns.course.slug)
    assign_course(socket, course)
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case socket.assigns.live_action do
        :settings ->
          unless socket.assigns.can_settings, do: raise(AmautaWeb.ForbiddenError)
          assign_settings_forms(socket)

        _tab ->
          socket
      end

    {:noreply, socket |> assign_section_filter(params["section"]) |> load_people()}
  end

  # Filtro de comisión (RF-COM-003). Quien está limitado a sus comisiones
  # (RF-COM-002) solo puede elegir entre ellas.
  defp assign_section_filter(socket, value) do
    filter =
      case socket.assigns.own_section_ids do
        [] ->
          if value == "none" or Enum.any?(socket.assigns.sections, &(&1.id == value)),
            do: value

        [first | _] = own ->
          if value in own, do: value, else: first
      end

    assign(socket, section_filter: filter)
  end

  defp load_people(%{assigns: %{live_action: :people}} = socket) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns
    enrollments = Enrollments.list(scope, course, %{"section" => filter})
    assign(socket, enrollments: enrollments)
  end

  defp load_people(socket), do: assign(socket, enrollments: [])

  defp enroll_form, do: to_form(%{"role" => "student", "section_id" => ""}, as: "enroll")

  defp assign_settings_forms(socket) do
    %{course: course, current_scope: scope} = socket.assigns
    pathways = movable_pathways(scope, course)

    assign(socket,
      form: to_form(Course.changeset(course, %{}), as: "course"),
      settings_form: to_form(Settings.changeset(course.settings, %{}), as: "settings"),
      periods: Periods.list(scope),
      pathways: pathways,
      stages: stages(scope, pathways, course.pathway_id),
      standalone:
        is_nil(course.pathway_id) or Authorization.can?(scope, "pathway.structure.update", course)
    )
  end

  # Trayectos a los que se puede llevar el curso: el actual y aquellos cuya
  # estructura la persona puede editar.
  defp movable_pathways(scope, course) do
    scope
    |> Pathways.list_visible()
    |> Enum.filter(
      &(&1.id == course.pathway_id or Authorization.can?(scope, "pathway.structure.update", &1))
    )
  end

  defp stages(_scope, _pathways, nil), do: []

  defp stages(scope, pathways, pathway_id) do
    case Enum.find(pathways, &(&1.id == pathway_id)) do
      nil -> []
      pathway -> Pathways.list_stages(scope, pathway)
    end
  end

  ## Ajustes

  @impl true
  def handle_event("change", %{"course" => params}, socket) do
    %{course: course, current_scope: scope, pathways: pathways} = socket.assigns

    {:noreply,
     assign(socket,
       form: to_form(Course.changeset(course, params), as: "course"),
       stages: stages(scope, pathways, blank_to_nil(params["pathway_id"]))
     )}
  end

  def handle_event("save", %{"course" => params}, socket) do
    scope = socket.assigns.current_scope
    params = Map.put(params, "course_id", socket.assigns.course.id)

    case Actions.run(UpdateCourse, scope, params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Changes saved."))
         |> push_navigate(to: Paths.course(scope, course, :settings))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "course"))}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  def handle_event("save_settings", %{"settings" => settings}, socket) do
    params = %{"course_id" => socket.assigns.course.id, "settings" => settings}

    case Actions.run(UpdateCourseSettings, socket.assigns.current_scope, params) do
      {:ok, _course} ->
        {:noreply,
         socket
         |> reload()
         |> assign_settings_forms()
         |> put_flash(:info, gettext("Changes saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           settings_form: to_form(changeset.changes.settings || changeset, as: "settings")
         )}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  def handle_event("regenerate_code", _params, socket),
    do: run(socket, RegenerateEnrollmentCode, gettext("New enrollment code generated."))

  def handle_event("publish", _params, socket),
    do:
      run(
        socket,
        PublishCourse,
        gettext_term(socket.assigns.current_scope, :course, "Published.")
      )

  def handle_event("archive", _params, socket) do
    info =
      gettext_term(socket.assigns.current_scope, :course, "Archived. It is now read-only.")

    run(socket, ArchiveCourse, info)
  end

  def handle_event("reopen", _params, socket),
    do:
      run(socket, ReopenCourse, gettext_term(socket.assigns.current_scope, :course, "Reopened."))

  ## Comisiones

  def handle_event("select_section", %{"section" => value}, socket) do
    %{current_scope: scope, course: course, live_action: tab} = socket.assigns
    params = if value == "", do: %{}, else: %{section: value}
    {:noreply, push_patch(socket, to: Paths.course(scope, course, tab, params))}
  end

  def handle_event("new_section", _params, socket),
    do: {:noreply, assign(socket, section_form: section_form(%{}), editing_section: nil)}

  def handle_event("edit_section", %{"id" => id}, socket) do
    section = Enum.find(socket.assigns.sections, &(&1.id == id))

    form =
      section_form(%{
        "name" => section.name,
        "schedule" => section.schedule,
        "room" => section.room
      })

    {:noreply, assign(socket, section_form: form, editing_section: section)}
  end

  def handle_event("cancel_section", _params, socket),
    do: {:noreply, assign(socket, section_form: nil, editing_section: nil)}

  def handle_event("save_section", %{"section" => params}, socket) do
    {action, params} =
      case socket.assigns.editing_section do
        nil -> {CreateSection, Map.put(params, "course_id", socket.assigns.course.id)}
        section -> {UpdateSection, Map.put(params, "section_id", section.id)}
      end

    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _section} ->
        {:noreply,
         socket |> reload() |> load_people() |> assign(section_form: nil, editing_section: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, section_form: to_form(changeset, as: "section"))}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  def handle_event("delete_section", %{"id" => id}, socket),
    do: run_people(socket, DeleteSection, %{"section_id" => id})

  ## Matrículas

  def handle_event("enroll_change", %{"enroll" => params}, socket) do
    q = String.trim(params["q"] || "")

    results =
      if String.length(q) < 2 do
        []
      else
        enrolled =
          socket.assigns.current_scope
          |> Enrollments.list(socket.assigns.course, %{"status" => "active"})
          |> MapSet.new(& &1.user_id)

        Directory.list(socket.assigns.current_scope, %{"q" => q, "status" => "active"}).entries
        |> Enum.reject(&MapSet.member?(enrolled, &1.id))
        |> Enum.take(6)
      end

    {:noreply,
     assign(socket,
       enroll_form: to_form(params, as: "enroll"),
       people_query: q,
       people_results: results
     )}
  end

  def handle_event("enroll", %{"id" => user_id}, socket) do
    form = socket.assigns.enroll_form

    params = %{
      "course_id" => socket.assigns.course.id,
      "user_id" => user_id,
      "role" => form[:role].value || "student",
      "section_id" => form[:section_id].value
    }

    case Actions.run(EnrollUser, socket.assigns.current_scope, params) do
      {:ok, _enrollment} ->
        {:noreply,
         socket
         |> reload()
         |> load_people()
         |> assign(people_query: "", people_results: [])
         |> assign(enroll_form: to_form(Map.put(form.params, "q", ""), as: "enroll"))
         |> put_flash(:info, gettext("Enrolled."))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("That person could not be enrolled."))}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  def handle_event(
        "move_enrollment",
        %{"enrollment_id" => id, "section_id" => section_id},
        socket
      ),
      do:
        run_people(socket, UpdateEnrollment, %{"enrollment_id" => id, "section_id" => section_id})

  def handle_event("suspend_enrollment", %{"id" => id}, socket),
    do: run_people(socket, UpdateEnrollment, %{"enrollment_id" => id, "status" => "suspended"})

  def handle_event("reactivate_enrollment", %{"id" => id}, socket),
    do: run_people(socket, UpdateEnrollment, %{"enrollment_id" => id, "status" => "active"})

  def handle_event("end_enrollment", %{"id" => id}, socket),
    do: run_people(socket, EndEnrollment, %{"enrollment_id" => id})

  defp run_people(socket, action, params) do
    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload()
         |> assign_section_filter(socket.assigns.section_filter)
         |> load_people()}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  defp section_form(params), do: to_form(params, as: "section")

  defp run(socket, action, info) do
    params = %{"course_id" => socket.assigns.course.id}

    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _course} ->
        socket = reload(socket)

        socket =
          if socket.assigns.live_action == :settings,
            do: assign_settings_forms(socket),
            else: socket

        {:noreply, put_flash(socket, :info, info)}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  defp error_flash(socket, :forbidden),
    do: put_flash(socket, :error, gettext("You don't have permission to do that."))

  defp error_flash(socket, :archived) do
    message =
      gettext_term(
        socket.assigns.current_scope,
        :course,
        "It is archived: reopen it to make changes."
      )

    put_flash(socket, :error, message)
  end

  defp error_flash(socket, _reason),
    do: put_flash(socket, :error, gettext("That could not be done."))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  ## Vista

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:courses}>
      <nav
        :if={@course.pathway}
        aria-label={gettext("Breadcrumbs")}
        class="mb-3 flex flex-wrap items-center gap-1 text-sm text-ink-muted"
      >
        <.link navigate={Paths.pathway(@current_scope, @course.pathway)} class="hover:text-ink">
          {@course.pathway.name}
        </.link>
        <span :if={@course.stage}>
          <.icon name="caret-right" class="size-3.5" /> {@course.stage.name}
        </span>
        <.badge :if={@course.stage && !@course.required} family="qolle" class="ms-1">
          {gettext_term(@current_scope, :course, "Optional")}
        </.badge>
      </nav>

      <.cover seed={@course.id} icon={@course.icon} family={@course.color} class="mb-4 h-28" />

      <.header class="pb-4">
        {@course.name}
        <:subtitle>
          <span class="inline-flex flex-wrap items-center gap-2">
            <span :if={@course.code}>{@course.code}</span>
            <span :if={@course.period}>{@course.period.name}</span>
            <.status_badge status={@course.status} current_scope={@current_scope} />
          </span>
        </:subtitle>
        <:actions>
          <div :if={@teaching != []} id="teaching-team" class="flex -space-x-2">
            <.avatar
              :for={enrollment <- Enum.take(@teaching, 4)}
              name={User.display_name(enrollment.user)}
              src={Paths.avatar(@current_scope, enrollment.user)}
              size="sm"
              class="ring-2 ring-paper"
            />
          </div>
          <div
            :if={@can_see_code and @course.settings.enrollment_code_enabled}
            id="enrollment-code"
            class="flex items-center gap-2 rounded-control border border-line bg-surface px-3 py-1.5 text-sm"
          >
            <span class="text-ink-muted">{gettext("Enrollment code")}</span>
            <.kbd>{@course.enrollment_code}</.kbd>
          </div>
        </:actions>
      </.header>

      <.form
        :if={@sections != []}
        for={%{}}
        as={:section_filter}
        id="section_selector"
        phx-change="select_section"
        class="mb-4 max-w-xs"
      >
        <.input
          name="section"
          type="select"
          value={@section_filter}
          prompt={
            if @own_section_ids == [], do: gettext_term(@current_scope, :section, "All %{terms}")
          }
          options={section_options(@current_scope, @sections, @own_section_ids)}
          aria-label={term_title(@current_scope, :section)}
        />
      </.form>

      <.tabs label={term_title(@current_scope, :course)} class="mb-6">
        <:tab
          :for={{action, icon, label} <- course_tabs(@can_settings)}
          patch={Paths.course(@current_scope, @course, action, tab_params(@section_filter))}
          active={@live_action == action}
          icon={icon}
        >
          {label}
        </:tab>
      </.tabs>

      <.feed :if={@live_action == :feed} current_scope={@current_scope} />
      <.content :if={@live_action == :content} current_scope={@current_scope} />
      <.people :if={@live_action == :people} {people_assigns(assigns)} />
      <.grades :if={@live_action == :grades} />
      <.settings
        :if={@live_action == :settings}
        course={@course}
        current_scope={@current_scope}
        can_update={@can_update}
        can_archive={@can_archive}
        form={@form}
        settings_form={@settings_form}
        periods={@periods}
        pathways={@pathways}
        stages={@stages}
        standalone={@standalone}
      />
    </Layouts.app>
    """
  end

  defp course_tabs(can_settings) do
    [
      {:feed, "chats-circle", gettext("Feed")},
      {:content, "book-open", gettext("Content")},
      {:people, "users", gettext("People")},
      {:grades, "clipboard-text", gettext("Grades")}
    ] ++ if(can_settings, do: [{:settings, "gear", gettext("Settings")}], else: [])
  end

  attr :current_scope, :map, required: true

  defp feed(assigns) do
    ~H"""
    <.empty_state icon="chats-circle" title={gettext("Nothing posted yet")}>
      {gettext_term(
        @current_scope,
        :course,
        "Announcements and conversations of the %{term} will appear here."
      )}
    </.empty_state>
    """
  end

  attr :current_scope, :map, required: true

  defp content(assigns) do
    ~H"""
    <.empty_state icon="book-open" title={gettext("There is no content yet")}>
      {gettext_term(
        @current_scope,
        :unit,
        "Content is organized in %{terms}, with pages, materials and assignments."
      )}
    </.empty_state>
    """
  end

  defp tab_params(nil), do: %{}
  defp tab_params(section), do: %{section: section}

  defp section_options(scope, sections, []) do
    Enum.map(sections, &{&1.name, &1.id}) ++
      [{gettext_term(scope, :section, "No %{term}"), "none"}]
  end

  defp section_options(_scope, sections, own) do
    for section <- sections, section.id in own, do: {section.name, section.id}
  end

  defp people_assigns(assigns) do
    Map.take(assigns, [
      :current_scope,
      :course,
      :sections,
      :enrollments,
      :section_filter,
      :can_enroll,
      :can_manage_sections,
      :section_form,
      :editing_section,
      :enroll_form,
      :people_results
    ])
  end

  attr :current_scope, :map, required: true
  attr :course, Course, required: true
  attr :sections, :list, required: true
  attr :enrollments, :list, required: true
  attr :section_filter, :string, default: nil
  attr :can_enroll, :boolean, required: true
  attr :can_manage_sections, :boolean, required: true
  attr :section_form, :any, default: nil
  attr :editing_section, :any, default: nil
  attr :enroll_form, :any, required: true
  attr :people_results, :list, required: true

  defp people(assigns) do
    {teaching, others} =
      Enum.split_with(assigns.enrollments, &(&1.role in Enrollment.teaching_roles()))

    assigns = assign(assigns, teaching: teaching, others: others)

    ~H"""
    <div class="grid gap-6">
      <.card :if={@can_enroll}>
        <:header>{gettext("Enroll")}</:header>
        <.form
          for={@enroll_form}
          id="enroll_form"
          phx-change="enroll_change"
          phx-submit="enroll_change"
        >
          <div class="grid gap-x-4 sm:grid-cols-3">
            <div class="sm:col-span-3">
              <.input
                field={@enroll_form[:q]}
                type="search"
                placeholder={gettext("Search by name or email")}
                aria-label={gettext("Search")}
                phx-debounce="300"
                autocomplete="off"
              />
            </div>
            <.input
              field={@enroll_form[:role]}
              type="select"
              label={gettext("Role")}
              options={Enum.map(Enrollment.roles(), &{Roles.name(&1), &1})}
            />
            <.input
              :if={@sections != []}
              field={@enroll_form[:section_id]}
              type="select"
              label={term_title(@current_scope, :section)}
              prompt={gettext_term(@current_scope, :section, "No %{term}")}
              options={Enum.map(@sections, &{&1.name, &1.id})}
            />
          </div>
        </.form>

        <ul :if={@people_results != []} id="enroll_results" class="divide-y divide-line">
          <li :for={user <- @people_results} class="flex items-center gap-3 py-2">
            <.avatar
              name={User.display_name(user)}
              src={Paths.avatar(@current_scope, user)}
              size="sm"
            />
            <span class="min-w-0 flex-1">
              <span class="block truncate">{User.display_name(user)}</span>
              <span class="block truncate text-sm text-ink-muted">{user.email}</span>
            </span>
            <.button
              size="sm"
              variant="secondary"
              icon="plus"
              phx-click="enroll"
              phx-value-id={user.id}
            >
              {gettext("Enroll")}
            </.button>
          </li>
        </ul>

        <:footer>
          <div class="flex flex-wrap items-center justify-between gap-2 text-sm text-ink-muted">
            <span>{gettext("Many at once? Use a CSV file.")}</span>
            <.button
              size="sm"
              variant="ghost"
              icon="upload-simple"
              navigate={Paths.import_enrollments(@current_scope, @course)}
            >
              {gettext("Import CSV")}
            </.button>
          </div>
        </:footer>
      </.card>

      <.card :if={@can_manage_sections or @sections != []}>
        <:header>{term_title(@current_scope, :section, 2)}</:header>

        <p :if={@sections == []} class="text-ink-muted">
          {gettext_term(
            @current_scope,
            :section,
            "Split the students into %{terms}, each with its teachers, schedule and room."
          )}
        </p>

        <ul :if={@sections != []} id="sections" class="divide-y divide-line">
          <li
            :for={section <- @sections}
            id={"section-#{section.id}"}
            class="flex items-center gap-3 py-2"
          >
            <span class="min-w-0 flex-1">
              <span class="block font-semibold">{section.name}</span>
              <span :if={section.schedule || section.room} class="block text-sm text-ink-muted">
                {[section.schedule, section.room] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")}
              </span>
            </span>
            <.icon_button
              :if={@can_manage_sections}
              icon="pencil-simple"
              label={gettext("Edit")}
              size="sm"
              phx-click="edit_section"
              phx-value-id={section.id}
            />
            <.icon_button
              :if={@can_manage_sections}
              icon="trash"
              label={gettext("Delete")}
              size="sm"
              variant="danger"
              phx-click="delete_section"
              phx-value-id={section.id}
              data-confirm={
                gettext_term(
                  @current_scope,
                  :section,
                  "Delete «%{name}»? Its students stay enrolled, without a %{term}.",
                  name: section.name
                )
              }
            />
          </li>
        </ul>

        <.form
          :if={@section_form}
          for={@section_form}
          id="section_form"
          phx-submit="save_section"
          class="mt-4"
        >
          <div class="grid gap-x-4 sm:grid-cols-3">
            <.input
              field={@section_form[:name]}
              label={gettext("Name")}
              placeholder={gettext("Section A · Morning")}
              required
            />
            <.input
              field={@section_form[:schedule]}
              label={gettext("Schedule")}
              placeholder={gettext("Mon and Wed, 8 to 10")}
            />
            <.input field={@section_form[:room]} label={gettext("Room")} placeholder="Aula 12" />
          </div>
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button type="button" variant="ghost" phx-click="cancel_section">
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>

        <.button
          :if={@can_manage_sections and !@section_form}
          variant="secondary"
          size="sm"
          icon="plus"
          phx-click="new_section"
          class="mt-4"
        >
          {gettext_term(@current_scope, :section, "New %{term}")}
        </.button>
      </.card>

      <.card>
        <:header>{gettext("Teaching team")}</:header>
        <p :if={@teaching == []} class="text-ink-muted">{gettext("Nobody assigned yet.")}</p>
        <.enrollment_table
          :if={@teaching != []}
          id="teaching"
          enrollments={@teaching}
          sections={@sections}
          can_enroll={@can_enroll}
          current_scope={@current_scope}
        />
      </.card>

      <.card>
        <:header>
          {gettext("Students")}
          <span class="ms-1 font-normal text-ink-muted">({length(@others)})</span>
        </:header>
        <p :if={@others == []} class="text-ink-muted">{gettext("Nobody enrolled yet.")}</p>
        <.enrollment_table
          :if={@others != []}
          id="students"
          enrollments={@others}
          sections={@sections}
          can_enroll={@can_enroll}
          current_scope={@current_scope}
        />
      </.card>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :enrollments, :list, required: true
  attr :sections, :list, required: true
  attr :can_enroll, :boolean, required: true
  attr :current_scope, :map, required: true

  defp enrollment_table(assigns) do
    ~H"""
    <.table id={@id} rows={@enrollments} row_id={&"enrollment-#{&1.id}"}>
      <:col :let={enrollment} label={gettext("Name")}>
        <div class="flex items-center gap-3">
          <.avatar
            name={User.display_name(enrollment.user)}
            src={Paths.avatar(@current_scope, enrollment.user)}
            size="sm"
          />
          <div class="min-w-0">
            <p class="font-semibold">{User.display_name(enrollment.user)}</p>
            <p class="truncate text-ink-muted">{enrollment.user.email}</p>
          </div>
        </div>
      </:col>
      <:col :let={enrollment} label={gettext("Role")}>
        <.badge family="anil">{Roles.name(enrollment.role)}</.badge>
        <.badge :if={enrollment.status == "suspended"} family="cochinilla" class="ms-1">
          {gettext("Suspended")}
        </.badge>
      </:col>
      <:col :let={enrollment} :if={@sections != []} label={term_title(@current_scope, :section)}>
        <.form
          :if={@can_enroll}
          for={%{}}
          as={:move}
          id={"move-#{enrollment.id}"}
          phx-change="move_enrollment"
        >
          <input type="hidden" name="enrollment_id" value={enrollment.id} />
          <.input
            name="section_id"
            type="select"
            value={enrollment.section_id}
            prompt={gettext_term(@current_scope, :section, "No %{term}")}
            options={Enum.map(@sections, &{&1.name, &1.id})}
            aria-label={term_title(@current_scope, :section)}
          />
        </.form>
        <span :if={!@can_enroll}>{enrollment.section && enrollment.section.name}</span>
      </:col>
      <:action :let={enrollment} :if={@can_enroll}>
        <.icon_button
          :if={enrollment.status == "active"}
          icon="lock"
          label={gettext("Suspend")}
          size="sm"
          phx-click="suspend_enrollment"
          phx-value-id={enrollment.id}
        />
        <.icon_button
          :if={enrollment.status == "suspended"}
          icon="key"
          label={gettext("Reactivate")}
          size="sm"
          phx-click="reactivate_enrollment"
          phx-value-id={enrollment.id}
        />
        <.icon_button
          icon="sign-out"
          label={gettext("Unenroll")}
          size="sm"
          variant="danger"
          phx-click="end_enrollment"
          phx-value-id={enrollment.id}
          data-confirm={
            gettext("Unenroll %{name}? Their submissions and grades are kept.",
              name: User.display_name(enrollment.user)
            )
          }
        />
      </:action>
    </.table>
    """
  end

  defp grades(assigns) do
    ~H"""
    <.empty_state icon="clipboard-text" title={gettext("There are no grades yet")}>
      {gettext("Grades appear here when assignments and assessments are graded.")}
    </.empty_state>
    """
  end

  attr :course, Course, required: true
  attr :current_scope, :map, required: true
  attr :can_update, :boolean, required: true
  attr :can_archive, :boolean, required: true
  attr :form, :any, required: true
  attr :settings_form, :any, required: true
  attr :periods, :list, required: true
  attr :pathways, :list, required: true
  attr :stages, :list, required: true
  attr :standalone, :boolean, required: true

  defp settings(assigns) do
    ~H"""
    <div class="grid gap-6">
      <.card>
        <:header>{gettext("Status")}</:header>
        <div class="flex flex-wrap items-center gap-3">
          <.status_badge status={@course.status} current_scope={@current_scope} />
          <.button
            :if={@can_update and @course.status == "draft"}
            icon="paper-plane-tilt"
            phx-click="publish"
          >
            {gettext("Publish")}
          </.button>
          <.button
            :if={@can_archive and @course.status != "archived"}
            variant="secondary"
            icon="archive"
            phx-click="archive"
            data-confirm={
              gettext_term(
                @current_scope,
                :course,
                "Archive it? It will become read-only until it is reopened."
              )
            }
          >
            {gettext("Archive")}
          </.button>
          <.button
            :if={@can_archive and @course.status == "archived"}
            icon="arrow-counter-clockwise"
            phx-click="reopen"
          >
            {gettext("Reopen")}
          </.button>
        </div>
      </.card>

      <.card :if={@can_update}>
        <:header>{gettext("Details")}</:header>
        <.form for={@form} id="course_form" phx-change="change" phx-submit="save">
          <.fields
            form={@form}
            current_scope={@current_scope}
            periods={@periods}
            pathways={@pathways}
            stages={@stages}
            standalone={@standalone}
            editing
          />
          <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
        </.form>
      </.card>

      <.card :if={@can_update}>
        <:header>{gettext("Settings")}</:header>
        <.form for={@settings_form} id="settings_form" phx-submit="save_settings">
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@settings_form[:visibility]}
              type="select"
              label={gettext("Who can see it")}
              options={options(@current_scope, :visibility)}
            />
            <.input
              field={@settings_form[:feed_posting]}
              type="select"
              label={gettext("Who can post in the feed")}
              options={options(@current_scope, :feed_posting)}
            />
            <.input
              field={@settings_form[:grading_scale]}
              type="select"
              label={gettext("Grading scale")}
              options={options(@current_scope, :grading_scale)}
            />
            <.input
              field={@settings_form[:unit_name]}
              type="select"
              label={gettext("Name of the units")}
              options={options(@current_scope, :unit_name)}
            />
          </div>
          <.input
            field={@settings_form[:comments_enabled]}
            type="checkbox"
            label={gettext("Allow comments on posts")}
          />
          <.input
            field={@settings_form[:enrollment_code_enabled]}
            type="checkbox"
            label={gettext("Allow joining with the enrollment code")}
          />
          <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
        </.form>
      </.card>

      <.card :if={@can_update}>
        <:header>{gettext("Enrollment code")}</:header>
        <div class="flex flex-wrap items-center gap-3">
          <.kbd>{@course.enrollment_code}</.kbd>
          <.button
            variant="secondary"
            size="sm"
            icon="arrow-counter-clockwise"
            phx-click="regenerate_code"
            data-confirm={gettext("Generate a new code? The current one will stop working.")}
          >
            {gettext("Generate a new one")}
          </.button>
        </div>
        <p class="mt-2 text-sm text-ink-muted">
          {gettext_term(
            @current_scope,
            :course,
            "Share it so students can join the %{term} on their own."
          )}
        </p>
      </.card>
    </div>
    """
  end

  defp options(scope, :visibility) do
    [
      {gettext("Only its participants"), "participants"},
      {gettext_term(scope, :institution, "Anyone in the %{term}"), "institution"}
    ]
  end

  defp options(_scope, :feed_posting) do
    [
      {gettext("Only the teaching team"), "teachers"},
      {gettext("Everyone"), "everyone"},
      {gettext("Everyone, with moderation"), "moderated"}
    ]
  end

  defp options(_scope, :grading_scale) do
    [
      {gettext("Numeric, from 0 to 10"), "numeric"},
      {gettext("Percentage"), "percentage"},
      {gettext("Pass or fail"), "pass_fail"}
    ]
  end

  defp options(_scope, :unit_name) do
    [
      {gettext("Unit"), "unit"},
      {gettext("Week"), "week"},
      {gettext("Class"), "class"},
      {gettext("Module"), "module"}
    ]
  end

  @doc "Campos del formulario de un curso, compartidos por el alta y la edición."
  attr :form, Phoenix.HTML.Form, required: true
  attr :current_scope, :map, required: true
  attr :periods, :list, required: true
  attr :pathways, :list, required: true
  attr :stages, :list, required: true
  attr :standalone, :boolean, default: true, doc: "si se puede dejar sin trayecto"
  attr :editing, :boolean, default: false

  def fields(assigns) do
    ~H"""
    <div class="grid gap-x-4 sm:grid-cols-3">
      <div class="sm:col-span-2">
        <.input
          field={@form[:name]}
          label={gettext("Name")}
          placeholder={gettext("Programming I")}
          required
        />
      </div>
      <.input field={@form[:code]} label={gettext("Code")} placeholder="PROG1" />
    </div>
    <div class="grid gap-x-4 sm:grid-cols-2">
      <.input
        field={@form[:period_id]}
        type="select"
        label={term_title(@current_scope, :period)}
        prompt={gettext_term(@current_scope, :period, "None (permanent)")}
        options={Enum.map(@periods, &{&1.name, &1.id})}
      />
      <.input
        field={@form[:pathway_id]}
        type="select"
        label={term_title(@current_scope, :pathway)}
        prompt={if @standalone, do: gettext_term(@current_scope, :pathway, "None (standalone)")}
        options={Enum.map(@pathways, &{&1.name, &1.id})}
      />
    </div>
    <div :if={@stages != []} class="grid gap-x-4 sm:grid-cols-2">
      <.input
        field={@form[:stage_id]}
        type="select"
        label={term_title(@current_scope, :stage)}
        prompt={gettext_term(@current_scope, :stage, "No %{term}")}
        options={Enum.map(@stages, &{&1.name, &1.id})}
      />
      <div class="sm:pt-7">
        <.input
          field={@form[:required]}
          type="checkbox"
          label={gettext("Required (unmark if it is optional)")}
        />
      </div>
    </div>
    <div class="grid gap-x-4 sm:grid-cols-2">
      <.input
        field={@form[:icon]}
        type="select"
        label={gettext("Icon")}
        options={Enum.map(Course.icons(), &{icon_label(&1), &1})}
      />
      <.input
        field={@form[:color]}
        type="select"
        label={gettext("Color")}
        options={Enum.map(Course.colors(), &{color_label(&1), &1})}
      />
    </div>
    <.input
      :if={@editing}
      field={@form[:slug]}
      label={gettext("Web address")}
      hint={gettext("Lowercase letters, digits and hyphens.")}
    />
    <.input field={@form[:description]} type="textarea" label={gettext("Description")} />
    """
  end

  defp icon_label("book-open"), do: gettext("Book")
  defp icon_label("code"), do: gettext("Programming")
  defp icon_label("calculator"), do: gettext("Calculator")
  defp icon_label("flask"), do: gettext("Flask")
  defp icon_label("globe-hemisphere-west"), do: gettext("Globe")
  defp icon_label("palette"), do: gettext("Palette")
  defp icon_label("music-notes"), do: gettext("Music")
  defp icon_label("translate"), do: gettext("Languages")
  defp icon_label("chart-line"), do: gettext("Chart")
  defp icon_label("scales"), do: gettext("Scales")
  defp icon_label("heartbeat"), do: gettext("Health")
  defp icon_label("leaf"), do: gettext("Leaf")

  defp color_label("anil"), do: gettext("Indigo")
  defp color_label("airampo"), do: gettext("Purple")
  defp color_label("chilca"), do: gettext("Green")
  defp color_label("qolle"), do: gettext("Yellow")
  defp color_label("cochinilla"), do: gettext("Red")
  defp color_label("nogal"), do: gettext("Brown")

  attr :status, :string, required: true
  attr :current_scope, :map, required: true

  def status_badge(assigns) do
    ~H"""
    <.badge family={status_family(@status)}>{status_label(@current_scope, @status)}</.badge>
    """
  end

  defp status_family("draft"), do: "qolle"
  defp status_family("published"), do: "chilca"
  defp status_family("archived"), do: "nogal"

  @doc "Estado del curso, concordado con el género del término."
  def status_label(scope, "draft"), do: gettext_term(scope, :course, "Draft")
  def status_label(scope, "published"), do: gettext_term(scope, :course, "Published")
  def status_label(scope, "archived"), do: gettext_term(scope, :course, "Archived")
end
