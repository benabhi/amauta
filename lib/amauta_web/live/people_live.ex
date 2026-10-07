defmodule AmautaWeb.PeopleLive do
  @moduledoc """
  Directorio de personas de la institución (RF-INS-004): búsqueda, filtros,
  alta manual con invitación, edición del perfil, suspensión y reenvío de
  la invitación. Ver exige `institution.users.view`; modificar,
  `institution.users.manage` (las acciones lo verifican de nuevo).
  """
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization}
  alias Amauta.Accounts.{Directory, User}

  alias Amauta.Accounts.Actions.{
    CreateUser,
    ReactivateUser,
    ResendInvitation,
    SuspendUser,
    UpdateUser
  }

  alias Amauta.Authorization.Roles
  alias AmautaWeb.Paths

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Authorization.can?(scope, "institution.users.view") do
      {:ok,
       assign(socket,
         page_title: gettext("People"),
         can_manage: Authorization.can?(scope, "institution.users.manage"),
         form: nil
       )}
    else
      raise AmautaWeb.ForbiddenError
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = Map.take(params, ~w(q status page))
    scope = socket.assigns.current_scope
    page = Directory.list(scope, filters)

    {:noreply,
     socket
     |> assign(filters: filters, page: page, roles: Directory.roles_by_user(scope, page.entries))
     |> assign_form(socket.assigns.live_action, params)}
  end

  defp assign_form(socket, :new, _params) do
    assign(socket, form: to_form(%{"send_invitation" => "true"}, as: "person"), editing: nil)
  end

  defp assign_form(socket, :edit, %{"id" => id}) do
    user = Enum.find(socket.assigns.page.entries, &(&1.id == id)) || load_user!(socket, id)
    assign(socket, form: to_form(User.profile_changeset(user, %{}), as: "person"), editing: user)
  end

  defp assign_form(socket, _action, _params), do: assign(socket, form: nil, editing: nil)

  defp load_user!(socket, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Amauta.Accounts.get_user!(socket.assigns.current_scope, id)
      :error -> raise AmautaWeb.NotFoundError
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params |> Map.take(~w(q status)) |> Enum.reject(fn {_k, v} -> v == "" end) |> Map.new()

    {:noreply, push_patch(socket, to: Paths.people(socket.assigns.current_scope, filters))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    scope = socket.assigns.current_scope

    {action, params, info} =
      case socket.assigns.editing do
        nil ->
          {CreateUser, params, gettext("Person added. The invitation is on its way.")}

        user ->
          {UpdateUser, Map.put(params, "user_id", user.id), gettext("Changes saved.")}
      end

    case Actions.run(action, scope, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_patch(to: Paths.people(scope, socket.assigns.filters))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "person"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("You don't have permission to do that."))}
    end
  end

  def handle_event("suspend", %{"id" => id}, socket),
    do: run(socket, SuspendUser, id, gettext("Person suspended."))

  def handle_event("reactivate", %{"id" => id}, socket),
    do: run(socket, ReactivateUser, id, gettext("Person reactivated."))

  def handle_event("resend", %{"id" => id}, socket),
    do: run(socket, ResendInvitation, id, gettext("Invitation sent again."))

  defp run(socket, action, id, info) do
    scope = socket.assigns.current_scope

    case Actions.run(action, scope, %{"user_id" => id}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_patch(to: Paths.people(scope, socket.assigns.filters))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:people}>
      <.header>
        {gettext("People")}
        <:subtitle>
          {ngettext("%{count} person", "%{count} people", @page.total)}
        </:subtitle>
        <:actions>
          <.button
            variant="secondary"
            icon="download-simple"
            href={Paths.export_people(@current_scope, @filters)}
          >
            {gettext("Export")}
          </.button>
          <.button
            :if={@can_manage}
            variant="secondary"
            icon="upload-simple"
            navigate={Paths.import_people(@current_scope)}
          >
            {gettext("Import CSV")}
          </.button>
          <.button :if={@can_manage} icon="plus" patch={Paths.new_person(@current_scope)}>
            {gettext("Add person")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@form} class="mb-6">
        <:header>{if @editing, do: User.display_name(@editing), else: gettext("New person")}</:header>
        <.form for={@form} id="person_form" phx-submit="save">
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:first_name]} label={gettext("First name")} required />
            <.input field={@form[:last_name]} label={gettext("Last name")} required />
            <.input
              field={@form[:preferred_name]}
              label={gettext("Preferred name")}
              hint={gettext("Optional: how the person wants to be called.")}
            />
            <.input
              :if={!@editing}
              field={@form[:email]}
              type="email"
              label={gettext("Email")}
              required
            />
          </div>
          <.input
            :if={!@editing}
            field={@form[:send_invitation]}
            type="checkbox"
            label={gettext("Send the invitation by email now")}
          />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button variant="ghost" patch={Paths.people(@current_scope, @filters)}>
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
            placeholder={gettext("Search by name or email")}
            phx-debounce="300"
            aria-label={gettext("Search")}
          />
        </div>
        <div class="w-52">
          <.input
            name="status"
            type="select"
            value={@filters["status"]}
            prompt={gettext("All statuses")}
            options={Enum.map(User.statuses(), &{status_label(&1), &1})}
            aria-label={gettext("Status")}
          />
        </div>
      </.form>

      <.empty_state :if={@page.entries == []} icon="users" title={gettext("Nobody here")}>
        {gettext("No person matches the search.")}
      </.empty_state>

      <.table :if={@page.entries != []} id="people" rows={@page.entries} row_id={&"person-#{&1.id}"}>
        <:col :let={user} label={gettext("Name")}>
          <div class="flex items-center gap-3">
            <.avatar
              name={User.display_name(user)}
              src={Paths.avatar(@current_scope, user)}
              size="sm"
            />
            <div class="min-w-0">
              <p class="font-semibold">{User.display_name(user)}</p>
              <p class="truncate text-ink-muted">{user.email}</p>
            </div>
          </div>
        </:col>
        <:col :let={user} label={gettext("Roles")}>
          <div class="flex flex-wrap gap-1">
            <.badge :for={role <- Map.get(@roles, user.id, [])} family="anil">
              {Roles.name(role)}
            </.badge>
          </div>
        </:col>
        <:col :let={user} label={gettext("Status")}>
          <.status_badge status={user.status} />
        </:col>
        <:action :let={user} :if={@can_manage}>
          <.icon_button
            icon="pencil-simple"
            label={gettext("Edit")}
            size="sm"
            phx-click={JS.patch(Paths.edit_person(@current_scope, user))}
          />
          <.icon_button
            :if={user.status == "invited"}
            icon="paper-plane-tilt"
            label={gettext("Send invitation again")}
            size="sm"
            phx-click="resend"
            phx-value-id={user.id}
          />
          <.icon_button
            :if={user.status in ["active", "invited"] and user.id != @current_scope.user.id}
            icon="lock"
            label={gettext("Suspend")}
            size="sm"
            phx-click="suspend"
            phx-value-id={user.id}
            data-confirm={
              gettext("Suspend %{name}? They will not be able to log in.",
                name: User.display_name(user)
              )
            }
          />
          <.icon_button
            :if={user.status == "suspended"}
            icon="key"
            label={gettext("Reactivate")}
            size="sm"
            phx-click="reactivate"
            phx-value-id={user.id}
          />
        </:action>
      </.table>

      <nav
        :if={@page.total > @page.per_page}
        class="mt-4 flex items-center justify-between text-sm"
        aria-label={gettext("Pagination")}
      >
        <.button
          :if={@page.page > 1}
          variant="secondary"
          size="sm"
          icon="arrow-left"
          patch={Paths.people(@current_scope, Map.put(@filters, "page", @page.page - 1))}
        >
          {gettext("Previous")}
        </.button>
        <span class="text-ink-muted">
          {gettext("Page %{page} of %{pages}",
            page: @page.page,
            pages: div(@page.total - 1, @page.per_page) + 1
          )}
        </span>
        <.button
          :if={@page.page * @page.per_page < @page.total}
          variant="secondary"
          size="sm"
          patch={Paths.people(@current_scope, Map.put(@filters, "page", @page.page + 1))}
        >
          {gettext("Next")}
        </.button>
      </nav>
    </Layouts.app>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <.badge family={status_family(@status)}>{status_label(@status)}</.badge>
    """
  end

  defp status_family("invited"), do: "qolle"
  defp status_family("active"), do: "chilca"
  defp status_family("suspended"), do: "cochinilla"
  defp status_family("archived"), do: "nogal"

  def status_label("invited"), do: gettext("Invitation pending")
  def status_label("active"), do: gettext("Active")
  def status_label("suspended"), do: gettext("Suspended")
  def status_label("archived"), do: gettext("Archived")
end
