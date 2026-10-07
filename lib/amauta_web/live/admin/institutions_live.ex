defmodule AmautaWeb.Admin.InstitutionsLive do
  @moduledoc "Instituciones de la instancia: listado y alta (RF-ADM-002)."
  use AmautaWeb, :live_view

  alias Amauta.Platform
  alias Amauta.Platform.Administration

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, institutions: Platform.list_institutions())}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket =
      case socket.assigns.live_action do
        :new -> assign(socket, form: to_form(Administration.change_institution()))
        :index -> assign(socket, form: nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"institution" => params}, socket) do
    changeset =
      params |> then(&Administration.change_institution(%Platform.Institution{}, &1))

    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"institution" => params}, socket) do
    case Administration.create_institution(socket.assigns.current_staff, params) do
      {:ok, institution} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Institution created. Now assign its administration."))
         |> push_navigate(to: ~p"/admin/institutions/#{institution.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, {:migration_failed, institution, _message}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext(
             "The institution was created but its database could not be prepared. Retry from its page."
           )
         )
         |> push_navigate(to: ~p"/admin/institutions/#{institution.id}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_staff={@current_staff}>
      <.header>
        {gettext("Institutions")}
        <:actions>
          <.button :if={@live_action == :index} patch={~p"/admin/institutions/new"} icon="plus">
            {gettext("New institution")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@form} class="mb-6">
        <:header>{gettext("New institution")}</:header>
        <.form for={@form} id="institution_form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label={gettext("Name")} required />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:short_name]} label={gettext("Short name")} />
            <.input
              field={@form[:slug]}
              label={gettext("Address")}
              hint={gettext("Lowercase letters, numbers and hyphens: it goes in the URL.")}
              required
            />
          </div>
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Creating...")}>{gettext("Create")}</.button>
            <.button variant="ghost" patch={~p"/admin"}>{gettext("Cancel")}</.button>
          </div>
        </.form>
      </.card>

      <.empty_state
        :if={@institutions == [] and !@form}
        icon="graduation-cap"
        title={gettext("There are no institutions yet")}
      >
        {gettext("Create the first one to start using Amauta.")}
        <:action>
          <.button patch={~p"/admin/institutions/new"} icon="plus">
            {gettext("New institution")}
          </.button>
        </:action>
      </.empty_state>

      <.table
        :if={@institutions != []}
        id="institutions"
        rows={@institutions}
        row_click={&JS.navigate(~p"/admin/institutions/#{&1.id}")}
      >
        <:col :let={i} label={gettext("Name")}>
          <span class="font-semibold">{i.name}</span>
        </:col>
        <:col :let={i} label={gettext("Address")}>
          <span class="font-mono text-sm">/{i.slug}</span>
        </:col>
        <:col :let={i} label={gettext("Status")}>
          <.status_badge institution={i} />
        </:col>
      </.table>
    </Layouts.admin>
    """
  end

  attr :institution, :map, required: true

  def status_badge(assigns) do
    ~H"""
    <.badge :if={@institution.migration_error} family="cochinilla" icon="warning">
      {gettext("Database error")}
    </.badge>
    <.badge
      :if={!@institution.migration_error && @institution.status == "active"}
      family="chilca"
    >
      {gettext("Active")}
    </.badge>
    <.badge :if={!@institution.migration_error && @institution.status == "suspended"} family="qolle">
      {gettext("Suspended")}
    </.badge>
    """
  end
end
