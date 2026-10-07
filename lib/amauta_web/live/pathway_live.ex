defmodule AmautaWeb.PathwayLive do
  @moduledoc """
  Detalle de un trayecto (RF-TRA-001 y RF-TRA-002): datos, estado, etapas
  ordenadas y responsables. Ver exige `pathway.view` sobre el trayecto;
  cada cambio, su propio permiso (las acciones lo verifican de nuevo). Un
  trayecto archivado es de solo lectura hasta que se reabre.
  """
  use AmautaWeb, :live_view

  alias Amauta.Accounts.{Directory, User}
  alias Amauta.{Actions, Authorization, Pathways}
  alias Amauta.Authorization.Actions.{AssignRole, RevokeRole}

  alias Amauta.Pathways.Actions.{
    AddStage,
    ArchivePathway,
    DeleteStage,
    MoveStage,
    PublishPathway,
    RenameStage,
    ReopenPathway,
    UpdatePathway
  }

  alias Amauta.Pathways.Pathway
  alias AmautaWeb.Paths

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    pathway = Pathways.get_by_slug(scope, slug) || raise AmautaWeb.NotFoundError

    unless Authorization.can?(scope, "pathway.view", pathway), do: raise(AmautaWeb.ForbiddenError)

    {:ok,
     socket
     |> assign(page_title: pathway.name, people_query: "", people_results: [])
     |> assign_pathway(pathway)
     |> assign(stage_form: stage_form(), editing_stage: nil)}
  end

  defp assign_pathway(socket, pathway) do
    scope = socket.assigns.current_scope
    can = &Authorization.can?(scope, &1, pathway)
    open = pathway.status != "archived"

    assign(socket,
      pathway: pathway,
      stages: Pathways.list_stages(scope, pathway),
      courses: Amauta.Courses.by_stage(scope, pathway),
      can_add_course: open and can.("institution.courses.create"),
      coordinators: Pathways.coordinators(scope, pathway),
      can_update: open and can.("pathway.update"),
      can_structure: open and can.("pathway.structure.update"),
      can_archive: can.("pathway.archive"),
      can_manage_people: open and can.("pathway.enrollments.manage")
    )
  end

  defp reload(socket) do
    scope = socket.assigns.current_scope
    pathway = Pathways.get(scope, socket.assigns.pathway.id)
    assign_pathway(socket, pathway)
  end

  defp stage_form(stage \\ nil),
    do: to_form(%{"name" => stage && stage.name}, as: "stage")

  @impl true
  def handle_params(_params, _url, socket) do
    form =
      if socket.assigns.live_action == :edit do
        unless socket.assigns.can_update, do: raise(AmautaWeb.ForbiddenError)
        to_form(Pathway.changeset(socket.assigns.pathway, %{}), as: "pathway")
      end

    {:noreply, assign(socket, form: form)}
  end

  ## Datos y estado

  @impl true
  def handle_event("save", %{"pathway" => params}, socket) do
    scope = socket.assigns.current_scope
    params = Map.put(params, "pathway_id", socket.assigns.pathway.id)

    case Actions.run(UpdatePathway, scope, params) do
      {:ok, pathway} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Changes saved."))
         |> push_navigate(to: Paths.pathway(scope, pathway))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "pathway"))}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  def handle_event("publish", _params, socket),
    do:
      transition(
        socket,
        PublishPathway,
        gettext_term(socket.assigns.current_scope, :pathway, "Published.")
      )

  def handle_event("archive", _params, socket),
    do:
      transition(
        socket,
        ArchivePathway,
        gettext_term(socket.assigns.current_scope, :pathway, "Archived. It is now read-only.")
      )

  def handle_event("reopen", _params, socket),
    do:
      transition(
        socket,
        ReopenPathway,
        gettext_term(socket.assigns.current_scope, :pathway, "Reopened.")
      )

  ## Etapas

  def handle_event("save_stage", %{"stage" => %{"name" => name}}, socket) do
    {action, params} =
      case socket.assigns.editing_stage do
        nil -> {AddStage, %{"pathway_id" => socket.assigns.pathway.id, "name" => name}}
        stage -> {RenameStage, %{"stage_id" => stage.id, "name" => name}}
      end

    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _stage} ->
        {:noreply, socket |> reload() |> assign(stage_form: stage_form(), editing_stage: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, stage_form: to_form(changeset, as: "stage"))}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason)}
    end
  end

  def handle_event("edit_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))
    {:noreply, assign(socket, editing_stage: stage, stage_form: stage_form(stage))}
  end

  def handle_event("cancel_stage", _params, socket),
    do: {:noreply, assign(socket, editing_stage: nil, stage_form: stage_form())}

  def handle_event("move_stage", %{"id" => id, "direction" => direction}, socket),
    do: run(socket, MoveStage, %{"stage_id" => id, "direction" => direction})

  def handle_event("delete_stage", %{"id" => id}, socket),
    do: run(socket, DeleteStage, %{"stage_id" => id})

  ## Responsables

  def handle_event("search_people", %{"q" => q}, socket) do
    results =
      if String.length(String.trim(q)) < 2 do
        []
      else
        current = MapSet.new(socket.assigns.coordinators, fn {user, _id} -> user.id end)

        Directory.list(socket.assigns.current_scope, %{"q" => q, "status" => "active"}).entries
        |> Enum.reject(&MapSet.member?(current, &1.id))
        |> Enum.take(6)
      end

    {:noreply, assign(socket, people_query: q, people_results: results)}
  end

  def handle_event("add_coordinator", %{"id" => user_id}, socket) do
    params = %{
      "user_id" => user_id,
      "role" => Pathways.coordinator_role(),
      "scope_type" => "pathway",
      "scope_id" => socket.assigns.pathway.id
    }

    socket |> assign(people_query: "", people_results: []) |> run(AssignRole, params)
  end

  def handle_event("remove_coordinator", %{"id" => assignment_id}, socket),
    do: run(socket, RevokeRole, %{"assignment_id" => assignment_id})

  defp run(socket, action, params) do
    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _} -> {:noreply, reload(socket)}
      {:error, reason} -> {:noreply, error_flash(socket, reason)}
    end
  end

  defp transition(socket, action, info) do
    params = %{"pathway_id" => socket.assigns.pathway.id}

    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _pathway} -> {:noreply, socket |> reload() |> put_flash(:info, info)}
      {:error, reason} -> {:noreply, error_flash(socket, reason)}
    end
  end

  defp error_flash(socket, :forbidden),
    do: put_flash(socket, :error, gettext("You don't have permission to do that."))

  defp error_flash(socket, :archived),
    do:
      put_flash(
        socket,
        :error,
        gettext_term(
          socket.assigns.current_scope,
          :pathway,
          "It is archived: reopen it to make changes."
        )
      )

  defp error_flash(socket, _reason),
    do: put_flash(socket, :error, gettext("That could not be done."))

  ## Vista

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:pathways}>
      <.button
        variant="ghost"
        size="sm"
        icon="arrow-left"
        navigate={Paths.pathways(@current_scope)}
        class="mb-4"
      >
        {term_title(@current_scope, :pathway, 2)}
      </.button>

      <.header>
        {@pathway.name}
        <:subtitle>
          <span class="inline-flex flex-wrap items-center gap-2">
            <span :if={@pathway.code}>{@pathway.code}</span>
            <.status_badge status={@pathway.status} current_scope={@current_scope} />
          </span>
        </:subtitle>
        <:actions>
          <.button
            :if={@can_manage_people}
            variant="secondary"
            icon="users"
            navigate={Paths.enroll_pathway(@current_scope, @pathway)}
          >
            {gettext("Enroll students")}
          </.button>
          <.button
            :if={@can_update and !@form}
            variant="secondary"
            icon="pencil-simple"
            patch={Paths.edit_pathway(@current_scope, @pathway)}
          >
            {gettext("Edit")}
          </.button>
          <.button
            :if={@can_update and @pathway.status == "draft"}
            icon="paper-plane-tilt"
            phx-click="publish"
          >
            {gettext("Publish")}
          </.button>
          <.button
            :if={@can_archive and @pathway.status != "archived"}
            variant="ghost"
            icon="archive"
            phx-click="archive"
            data-confirm={
              gettext_term(
                @current_scope,
                :pathway,
                "Archive it? It will become read-only until it is reopened."
              )
            }
          >
            {gettext("Archive")}
          </.button>
          <.button
            :if={@can_archive and @pathway.status == "archived"}
            icon="arrow-counter-clockwise"
            phx-click="reopen"
          >
            {gettext("Reopen")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@form} class="mb-6">
        <:header>{gettext("Edit")}</:header>
        <.form for={@form} id="pathway_form" phx-submit="save">
          <.fields form={@form} current_scope={@current_scope} />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button variant="ghost" patch={Paths.pathway(@current_scope, @pathway)}>
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>
      </.card>

      <p :if={@pathway.description && !@form} class="mb-8 max-w-prose whitespace-pre-line">
        {@pathway.description}
      </p>

      <div class="grid gap-6 lg:grid-cols-3">
        <.card class="lg:col-span-2">
          <:header>{term_title(@current_scope, :stage, 2)}</:header>

          <.empty_state
            :if={@stages == []}
            icon="path"
            title={gettext_term(@current_scope, :stage, "There are no %{terms} yet")}
          >
            {gettext_term(
              @current_scope,
              :stage,
              "Add the first %{term}, for example «1st year»."
            )}
          </.empty_state>

          <.table :if={@stages != []} id="stages" rows={@stages} row_id={&"stage-#{&1.id}"}>
            <:col :let={stage} label="#">{stage.position}</:col>
            <:col :let={stage} label={gettext("Name")}>
              <span class="font-semibold">{stage.name}</span>
            </:col>
            <:col :let={stage} label={term_title(@current_scope, :course, 2)}>
              <.course_links courses={Map.get(@courses, stage.id, [])} current_scope={@current_scope} />
            </:col>
            <:action :let={stage} :if={@can_structure}>
              <.icon_button
                icon="arrow-up"
                label={gettext("Move up")}
                size="sm"
                disabled={stage.position == 1}
                phx-click="move_stage"
                phx-value-id={stage.id}
                phx-value-direction="up"
              />
              <.icon_button
                icon="arrow-down"
                label={gettext("Move down")}
                size="sm"
                disabled={stage.position == length(@stages)}
                phx-click="move_stage"
                phx-value-id={stage.id}
                phx-value-direction="down"
              />
              <.icon_button
                icon="pencil-simple"
                label={gettext("Rename")}
                size="sm"
                phx-click="edit_stage"
                phx-value-id={stage.id}
              />
              <.icon_button
                icon="trash"
                label={gettext("Delete")}
                size="sm"
                variant="danger"
                phx-click="delete_stage"
                phx-value-id={stage.id}
                data-confirm={gettext("Delete «%{name}»?", name: stage.name)}
              />
            </:action>
          </.table>

          <div :if={@courses[nil]} id="courses-without-stage" class="mt-4">
            <p class="mb-1 text-sm font-semibold text-ink-muted">{gettext("Without a stage")}</p>
            <.course_links courses={@courses[nil]} current_scope={@current_scope} />
          </div>

          <.button
            :if={@can_add_course}
            variant="secondary"
            size="sm"
            icon="plus"
            navigate={Paths.new_course(@current_scope, %{pathway_id: @pathway.id})}
            class="mt-4"
          >
            {gettext_term(@current_scope, :course, "New %{term}")}
          </.button>

          <.form
            :if={@can_structure}
            for={@stage_form}
            id="stage_form"
            phx-submit="save_stage"
            class="mt-4 flex flex-wrap items-start gap-2"
          >
            <div class="min-w-48 flex-1">
              <.input
                field={@stage_form[:name]}
                placeholder={
                  if @editing_stage,
                    do: gettext("New name"),
                    else: gettext_term(@current_scope, :stage, "Name of the new %{term}")
                }
                aria-label={gettext("Name")}
                required
              />
            </div>
            <.button icon={if @editing_stage, do: "check", else: "plus"}>
              {if @editing_stage,
                do: gettext("Rename"),
                else: gettext_term(@current_scope, :stage, "Add %{term}")}
            </.button>
            <.button
              :if={@editing_stage}
              type="button"
              variant="ghost"
              phx-click="cancel_stage"
            >
              {gettext("Cancel")}
            </.button>
          </.form>
        </.card>

        <.card>
          <:header>{gettext("Coordinators")}</:header>

          <p :if={@coordinators == []} class="text-ink-muted">
            {gettext("Nobody coordinates it yet.")}
          </p>

          <ul :if={@coordinators != []} id="coordinators" class="divide-y divide-line">
            <li
              :for={{user, assignment_id} <- @coordinators}
              id={"coordinator-#{user.id}"}
              class="flex items-center gap-3 py-2"
            >
              <.avatar
                name={User.display_name(user)}
                src={Paths.avatar(@current_scope, user)}
                size="sm"
              />
              <span class="min-w-0 flex-1 truncate">{User.display_name(user)}</span>
              <.icon_button
                :if={@can_manage_people}
                icon="x"
                label={gettext("Remove %{name}", name: User.display_name(user))}
                size="sm"
                phx-click="remove_coordinator"
                phx-value-id={assignment_id}
              />
            </li>
          </ul>

          <.form
            :if={@can_manage_people}
            for={%{}}
            as={:people}
            id="coordinator_search"
            phx-change="search_people"
            phx-submit="search_people"
            class="mt-4"
          >
            <.input
              name="q"
              value={@people_query}
              type="search"
              placeholder={gettext("Search by name or email")}
              aria-label={gettext("Add a coordinator")}
              phx-debounce="300"
              autocomplete="off"
            />
          </.form>

          <ul :if={@people_results != []} id="people_results" class="divide-y divide-line">
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
              <.icon_button
                icon="plus"
                label={gettext("Add %{name}", name: User.display_name(user))}
                size="sm"
                variant="secondary"
                phx-click="add_coordinator"
                phx-value-id={user.id}
              />
            </li>
          </ul>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  attr :courses, :list, required: true
  attr :current_scope, :map, required: true

  # Cursos de una etapa: enlaces, con los optativos marcados.
  defp course_links(assigns) do
    ~H"""
    <ul class="flex flex-wrap gap-x-3 gap-y-1">
      <li :for={course <- @courses} class="inline-flex items-center gap-1">
        <.link
          navigate={Paths.course(@current_scope, course)}
          class="underline-offset-2 hover:underline"
        >
          {course.name}
        </.link>
        <.badge :if={!course.required} family="qolle">
          {gettext_term(@current_scope, :course, "Optional")}
        </.badge>
      </li>
    </ul>
    """
  end

  @doc "Campos del formulario de un trayecto, compartidos por el alta y la edición."
  attr :form, Phoenix.HTML.Form, required: true
  attr :current_scope, :map, required: true

  def fields(assigns) do
    ~H"""
    <div class="grid gap-x-4 sm:grid-cols-3">
      <div class="sm:col-span-2">
        <.input
          field={@form[:name]}
          label={gettext("Name")}
          placeholder={gettext("Bachelor's degree in Computer Science")}
          required
        />
      </div>
      <.input field={@form[:code]} label={gettext("Code")} placeholder="LSI" />
    </div>
    <.input
      field={@form[:slug]}
      label={gettext("Web address")}
      hint={
        gettext("Optional: it is generated from the name. Lowercase letters, digits and hyphens.")
      }
    />
    <.input field={@form[:description]} type="textarea" label={gettext("Description")} />
    """
  end

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

  @doc "Estado del trayecto, concordado con el género del término."
  def status_label(scope, "draft"), do: gettext_term(scope, :pathway, "Draft")
  def status_label(scope, "published"), do: gettext_term(scope, :pathway, "Published")
  def status_label(scope, "archived"), do: gettext_term(scope, :pathway, "Archived")
end
