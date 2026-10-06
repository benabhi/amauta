defmodule AmautaWeb.Admin.InstitutionLive do
  @moduledoc """
  Una institución, vista por la superadministración: datos, estado,
  reintento de migraciones y administración (RF-ADM-002, 003 y 006).
  """
  use AmautaWeb, :live_view

  alias Amauta.Accounts.User
  alias Amauta.Platform
  alias Amauta.Platform.Administration
  alias Amauta.Tenancy.Migrator
  alias AmautaWeb.{Admin.InstitutionsLive, Paths}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, load(socket, Platform.get_institution!(id))}
      :error -> raise AmautaWeb.NotFoundError
    end
  end

  defp load(socket, institution) do
    socket
    |> assign(institution: institution)
    |> assign(form: to_form(Administration.change_institution(institution)))
    |> assign(admin_form: to_form(%{}, as: "admin"))
    |> assign(admins: admins(institution))
  end

  defp admins(%{migration_error: nil} = institution),
    do: Administration.list_admins(institution)

  defp admins(_institution), do: []

  @impl true
  def handle_event("validate", %{"institution" => params}, socket) do
    changeset = Administration.change_institution(socket.assigns.institution, params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"institution" => params}, socket) do
    %{current_staff: staff, institution: institution} = socket.assigns

    case Administration.update_institution(staff, institution, params) do
      {:ok, updated} ->
        {:noreply, socket |> put_flash(:info, gettext("Changes saved.")) |> load(updated)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("toggle_status", _params, socket) do
    %{current_staff: staff, institution: institution} = socket.assigns

    {:ok, updated} =
      if institution.status == "active",
        do: Administration.suspend_institution(staff, institution),
        else: Administration.activate_institution(staff, institution)

    {:noreply, load(socket, updated)}
  end

  def handle_event("retry_migration", _params, socket) do
    institution = socket.assigns.institution

    socket =
      case Migrator.migrate(institution) do
        {:ok, _} -> put_flash(socket, :info, gettext("Database ready."))
        {:error, _} -> put_flash(socket, :error, gettext("The migration failed again."))
      end

    {:noreply, load(socket, Platform.get_institution!(institution.id))}
  end

  def handle_event("assign_admin", %{"admin" => params}, socket) do
    %{current_staff: staff, institution: institution} = socket.assigns
    url_fun = &Paths.absolute(Paths.log_in(institution, &1))

    case Administration.assign_admin(staff, institution, params, url_fun) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("%{name} is now an administrator and got an email to log in.",
             name: user.first_name
           )
         )
         |> load(institution)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, admin_form: to_form(changeset, as: "admin"))}
    end
  end

  def handle_event("revoke_admin", %{"assignment" => id}, socket) do
    %{current_staff: staff, institution: institution} = socket.assigns
    :ok = Administration.revoke_admin(staff, institution, id)

    {:noreply,
     socket |> put_flash(:info, gettext("Administration removed.")) |> load(institution)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_staff={@current_staff}>
      <.header>
        {@institution.name}
        <:subtitle>
          <span class="font-mono">/{@institution.slug}</span>
          <InstitutionsLive.status_badge institution={@institution} />
        </:subtitle>
        <:actions>
          <.button
            variant="secondary"
            icon="arrow-right"
            href={Paths.log_in(@institution)}
            target="_blank"
          >
            {gettext("Open")}
          </.button>
        </:actions>
      </.header>

      <div class="flex flex-col gap-6">
        <.card :if={@institution.migration_error}>
          <:header>{gettext("Database")}</:header>
          <p class="mb-3 text-sm text-ink-muted">
            {gettext("The last migration of this institution failed:")}
          </p>
          <pre class="mb-4 overflow-x-auto rounded-control bg-surface-sunken p-3 font-mono text-xs">{@institution.migration_error}</pre>
          <.button phx-click="retry_migration" icon="circle-notch">{gettext("Retry")}</.button>
        </.card>

        <.card>
          <:header>{gettext("Administration")}</:header>
          <ul :if={@admins != []} class="mb-4 divide-y divide-line">
            <li :for={{user, assignment} <- @admins} class="flex items-center gap-3 py-2">
              <.avatar name={User.display_name(user)} size="sm" />
              <div class="min-w-0 flex-1">
                <p class="font-semibold">{User.display_name(user)}</p>
                <p class="truncate text-sm text-ink-muted">{user.email}</p>
              </div>
              <.icon_button
                icon="trash"
                label={gettext("Remove administration")}
                phx-click="revoke_admin"
                phx-value-assignment={assignment.id}
                data-confirm={
                  gettext("Remove the administration from %{name}?", name: user.first_name)
                }
              />
            </li>
          </ul>
          <p :if={@admins == []} class="mb-4 text-sm text-ink-muted">
            {gettext("This institution has no administrators yet.")}
          </p>
          <.form
            :if={!@institution.migration_error}
            for={@admin_form}
            id="admin_form"
            phx-submit="assign_admin"
          >
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@admin_form[:first_name]} label={gettext("First name")} required />
              <.input field={@admin_form[:last_name]} label={gettext("Last name")} required />
            </div>
            <.input field={@admin_form[:email]} type="email" label={gettext("Email")} required />
            <.button icon="envelope" variant="secondary">{gettext("Assign and invite")}</.button>
          </.form>
        </.card>

        <.card>
          <:header>{gettext("Details")}</:header>
          <.form for={@form} id="institution_form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} label={gettext("Name")} required />
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@form[:short_name]} label={gettext("Short name")} />
              <.input field={@form[:slug]} label={gettext("Address")} required />
            </div>
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
          </.form>
        </.card>

        <.card>
          <:header>{gettext("Status")}</:header>
          <p class="mb-4 text-sm text-ink-muted">
            {gettext("A suspended institution keeps all its data, but nobody can log in.")}
          </p>
          <.button
            variant={if @institution.status == "active", do: "danger", else: "secondary"}
            phx-click="toggle_status"
            data-confirm={
              if @institution.status == "active",
                do:
                  gettext("Suspend %{name}? Nobody will be able to log in.", name: @institution.name)
            }
          >
            {if @institution.status == "active",
              do: gettext("Suspend institution"),
              else: gettext("Reactivate institution")}
          </.button>
        </.card>
      </div>
    </Layouts.admin>
    """
  end
end
