defmodule AmautaWeb.PathwayEnrollLive do
  @moduledoc """
  Matriculación al trayecto (RF-TRA-003): se eligen estudiantes y se los
  matricula en los cursos del trayecto (todos, solo los obligatorios o los
  de una etapa). La comisión se asigna después, en cada curso. Exige
  `pathway.enrollments.manage` (la acción lo verifica de nuevo).
  """
  use AmautaWeb, :live_view

  alias Amauta.Accounts.{Directory, User}
  alias Amauta.{Actions, Authorization, Pathways}
  alias Amauta.Enrollments.Actions.EnrollInPathway
  alias AmautaWeb.Paths

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    pathway = Pathways.get_by_slug(scope, slug) || raise AmautaWeb.NotFoundError

    unless pathway.status != "archived" and
             Authorization.can?(scope, "pathway.enrollments.manage", pathway) do
      raise AmautaWeb.ForbiddenError
    end

    {:ok,
     assign(socket,
       page_title: gettext("Enroll students"),
       pathway: pathway,
       stages: Pathways.list_stages(scope, pathway),
       selected: [],
       results: [],
       form: to_form(%{"q" => "", "propagation" => "all", "stage_id" => ""}, as: "enroll"),
       result: nil
     )}
  end

  @impl true
  def handle_event("change", %{"enroll" => params}, socket) do
    q = String.trim(params["q"] || "")
    selected_ids = MapSet.new(socket.assigns.selected, & &1.id)

    results =
      if String.length(q) < 2 do
        []
      else
        Directory.list(socket.assigns.current_scope, %{"q" => q, "status" => "active"}).entries
        |> Enum.reject(&MapSet.member?(selected_ids, &1.id))
        |> Enum.take(8)
      end

    {:noreply, assign(socket, form: to_form(params, as: "enroll"), results: results)}
  end

  def handle_event("add", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.results, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      user ->
        {:noreply,
         assign(socket,
           selected: socket.assigns.selected ++ [user],
           results: Enum.reject(socket.assigns.results, &(&1.id == id))
         )}
    end
  end

  def handle_event("remove", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected: Enum.reject(socket.assigns.selected, &(&1.id == id)))}

  def handle_event("submit", _params, socket) do
    %{current_scope: scope, pathway: pathway, selected: selected, form: form} = socket.assigns

    params = %{
      "pathway_id" => pathway.id,
      "user_ids" => Enum.map(selected, & &1.id),
      "propagation" => form[:propagation].value,
      "stage_id" => form[:stage_id].value
    }

    case Actions.run(EnrollInPathway, scope, params) do
      {:ok, result} ->
        {:noreply, assign(socket, result: result, selected: [], results: [])}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext_term(scope, :stage, "Choose at least one person and, if needed, the %{term}.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:pathways}>
      <.header>
        {gettext("Enroll students")}
        <:subtitle>{@pathway.name}</:subtitle>
        <:actions>
          <.button
            variant="ghost"
            icon="arrow-left"
            navigate={Paths.pathway(@current_scope, @pathway)}
          >
            {gettext("Back")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@result} class="mb-6">
        <:header>{gettext("Done")}</:header>
        <p id="enroll_result">
          {ngettext(
            "%{count} enrollment created",
            "%{count} enrollments created",
            @result.enrolled
          )} · {@result.courses} {term(@current_scope, :course, @result.courses)} · {ngettext(
            "%{count} already enrolled",
            "%{count} already enrolled",
            @result.skipped
          )}
        </p>
      </.card>

      <.card>
        <.form for={@form} id="pathway_enroll_form" phx-change="change" phx-submit="change">
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@form[:propagation]}
              type="select"
              label={gettext_term(@current_scope, :course, "In which %{terms}")}
              options={[
                {gettext_term(@current_scope, :course, "All the %{terms}"), "all"},
                {gettext("Only the required ones"), "required"},
                {gettext_term(@current_scope, :stage, "Those of one %{term}"), "stage"}
              ]}
            />
            <.input
              :if={@form[:propagation].value == "stage"}
              field={@form[:stage_id]}
              type="select"
              label={term_title(@current_scope, :stage)}
              prompt={gettext("Choose one")}
              options={Enum.map(@stages, &{&1.name, &1.id})}
            />
          </div>

          <.input
            field={@form[:q]}
            type="search"
            label={gettext("Students")}
            placeholder={gettext("Search by name or email")}
            phx-debounce="300"
            autocomplete="off"
          />

          <ul :if={@results != []} id="results" class="mb-4 divide-y divide-line">
            <li :for={user <- @results} class="flex items-center gap-3 py-2">
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
                type="button"
                icon="plus"
                label={gettext("Add %{name}", name: User.display_name(user))}
                size="sm"
                variant="secondary"
                phx-click="add"
                phx-value-id={user.id}
              />
            </li>
          </ul>

          <div :if={@selected != []} id="selected" class="mb-4 flex flex-wrap gap-2">
            <span
              :for={user <- @selected}
              class="inline-flex items-center gap-1 rounded-full bg-surface-sunken py-1 ps-3 pe-1 text-sm"
            >
              {User.display_name(user)}
              <.icon_button
                type="button"
                icon="x"
                label={gettext("Remove %{name}", name: User.display_name(user))}
                size="sm"
                phx-click="remove"
                phx-value-id={user.id}
              />
            </span>
          </div>

          <.button
            type="button"
            icon="check"
            disabled={@selected == []}
            phx-click="submit"
            phx-disable-with={gettext("Enrolling...")}
          >
            {ngettext("Enroll %{count} person", "Enroll %{count} people", length(@selected))}
          </.button>
        </.form>
      </.card>
    </Layouts.app>
    """
  end
end
