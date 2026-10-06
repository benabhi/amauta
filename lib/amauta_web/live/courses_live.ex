defmodule AmautaWeb.CoursesLive do
  @moduledoc """
  Lista de cursos (RF-CUR-001) y alta de uno nuevo. Cada persona ve los
  cursos que puede ver (`Amauta.Courses.list_visible/2`); los borradores,
  solo quienes pueden editarlos. Crear exige `institution.courses.create`
  en la institución o en algún trayecto.
  """
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization, Courses, Pathways, Periods}
  alias Amauta.Courses.Actions.CreateCourse
  alias Amauta.Courses.Course
  alias AmautaWeb.{CourseLive, Paths}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    pathways = creatable_pathways(scope)
    standalone = Authorization.can?(scope, "institution.courses.create")

    {:ok,
     assign(socket,
       page_title: term_title(scope, :course, 2),
       periods: Periods.list(scope),
       pathways: pathways,
       can_create_standalone: standalone,
       can_create: standalone or pathways != [],
       form: nil
     )}
  end

  # Trayectos donde la persona puede crear cursos.
  defp creatable_pathways(scope) do
    scope
    |> Pathways.list_visible()
    |> Enum.filter(&Authorization.can?(scope, "institution.courses.create", &1))
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = Map.take(params, ~w(q status period_id))
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(filters: filters, courses: visible_courses(scope, filters))
     |> assign_form(socket.assigns.live_action, params)}
  end

  defp visible_courses(scope, filters) do
    scope
    |> Courses.list_visible(filters)
    |> Enum.filter(&(&1.status != "draft" or Authorization.can?(scope, "course.update", &1)))
  end

  defp assign_form(socket, :new, params) do
    unless socket.assigns.can_create, do: raise(AmautaWeb.ForbiddenError)

    attrs = %{
      "pathway_id" => params["pathway_id"],
      "stage_id" => params["stage_id"],
      "period_id" => with(%{id: id} <- Periods.current(socket.assigns.current_scope), do: id)
    }

    changeset = Course.changeset(%Course{}, attrs)
    assign(socket, form: to_form(changeset, as: "course"), stages: stages_for(socket, attrs))
  end

  defp assign_form(socket, _action, _params), do: assign(socket, form: nil, stages: [])

  defp stages_for(socket, %{"pathway_id" => id}) when id not in [nil, ""] do
    case Enum.find(socket.assigns.pathways, &(&1.id == id)) do
      nil -> []
      pathway -> Pathways.list_stages(socket.assigns.current_scope, pathway)
    end
  end

  defp stages_for(_socket, _attrs), do: []

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(~w(q status period_id))
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Map.new()

    {:noreply, push_patch(socket, to: Paths.courses(socket.assigns.current_scope, filters))}
  end

  def handle_event("change", %{"course" => params}, socket) do
    changeset = Course.changeset(%Course{}, params)

    {:noreply,
     assign(socket, form: to_form(changeset, as: "course"), stages: stages_for(socket, params))}
  end

  def handle_event("save", %{"course" => params}, socket) do
    scope = socket.assigns.current_scope

    case Actions.run(CreateCourse, scope, params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext_term(scope, :course, "The %{term} was created."))
         |> push_navigate(to: Paths.course(scope, course))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "course"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You don't have permission to do that."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:courses}>
      <.header>
        {term_title(@current_scope, :course, 2)}
        <:subtitle>
          {ngettext("%{count} result", "%{count} results", length(@courses))}
        </:subtitle>
        <:actions>
          <.button :if={@can_create} icon="plus" patch={Paths.new_course(@current_scope)}>
            {gettext_term(@current_scope, :course, "New %{term}")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@form} class="mb-6">
        <:header>{gettext_term(@current_scope, :course, "New %{term}")}</:header>
        <.form for={@form} id="course_form" phx-change="change" phx-submit="save">
          <CourseLive.fields
            form={@form}
            current_scope={@current_scope}
            periods={@periods}
            pathways={@pathways}
            stages={@stages}
            standalone={@can_create_standalone}
          />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Create")}</.button>
            <.button variant="ghost" patch={Paths.courses(@current_scope, @filters)}>
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>
      </.card>

      <.form
        for={%{}}
        as={:filters}
        id="filters"
        phx-change="filter"
        class="mb-4 flex flex-wrap gap-3"
      >
        <div class="min-w-60 flex-1">
          <.input
            name="q"
            value={@filters["q"]}
            type="search"
            placeholder={gettext("Search by name or code")}
            phx-debounce="300"
            aria-label={gettext("Search")}
          />
        </div>
        <div class="w-52">
          <.input
            name="period_id"
            type="select"
            value={@filters["period_id"]}
            prompt={gettext_term(@current_scope, :period, "Any %{term}")}
            options={Enum.map(@periods, &{&1.name, &1.id})}
            aria-label={term_title(@current_scope, :period)}
          />
        </div>
        <div class="w-44">
          <.input
            name="status"
            type="select"
            value={@filters["status"]}
            prompt={gettext("Not archived")}
            options={Enum.map(Course.statuses(), &{CourseLive.status_label(@current_scope, &1), &1})}
            aria-label={gettext("Status")}
          />
        </div>
      </.form>

      <.empty_state
        :if={@courses == []}
        icon="book-open"
        title={gettext_term(@current_scope, :course, "There are no %{terms} here")}
      >
        {gettext_term(
          @current_scope,
          :course,
          "Each %{term} has its feed, content, people and grades."
        )}
      </.empty_state>

      <ul :if={@courses != []} id="courses" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <li :for={course <- @courses} id={"course-#{course.id}"}>
          <.tile
            navigate={Paths.course(@current_scope, course)}
            icon={course.icon}
            family={course.color}
            title={course.name}
          >
            <:subtitle>
              {[course.code, course.period && course.period.name]
              |> Enum.reject(&is_nil/1)
              |> Enum.join(" · ")}
            </:subtitle>
            <:badge>
              <CourseLive.status_badge status={course.status} current_scope={@current_scope} />
            </:badge>
          </.tile>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
