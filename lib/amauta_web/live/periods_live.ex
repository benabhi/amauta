defmodule AmautaWeb.PeriodsLive do
  @moduledoc """
  Períodos lectivos de la institución (RF-INS-009): lista, alta, edición y
  período actual. Exige `institution.periods.manage` (las acciones lo
  verifican de nuevo).
  """
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization, Periods}
  alias Amauta.Periods.AcademicPeriod
  alias Amauta.Periods.Actions.{CreatePeriod, SetCurrentPeriod, UpdatePeriod}
  alias AmautaWeb.{Format, Paths}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Authorization.can?(scope, "institution.periods.manage") do
      {:ok, assign(socket, page_title: term_title(scope, :period, 2), form: nil, editing: nil)}
    else
      raise AmautaWeb.ForbiddenError
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(periods: Periods.list(scope))
     |> assign_form(socket.assigns.live_action, params)}
  end

  defp assign_form(socket, :new, _params) do
    assign(socket,
      form: to_form(AcademicPeriod.changeset(%AcademicPeriod{}, %{}), as: "period"),
      editing: nil
    )
  end

  defp assign_form(socket, :edit, %{"id" => id}) do
    case Periods.get(socket.assigns.current_scope, id) do
      nil ->
        raise AmautaWeb.NotFoundError

      period ->
        assign(socket,
          form: to_form(AcademicPeriod.changeset(period, %{}), as: "period"),
          editing: period
        )
    end
  end

  defp assign_form(socket, _action, _params), do: assign(socket, form: nil, editing: nil)

  @impl true
  def handle_event("save", %{"period" => params}, socket) do
    scope = socket.assigns.current_scope

    {action, params} =
      case socket.assigns.editing do
        nil -> {CreatePeriod, params}
        period -> {UpdatePeriod, Map.put(params, "period_id", period.id)}
      end

    case Actions.run(action, scope, params) do
      {:ok, _period} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Changes saved."))
         |> push_patch(to: Paths.periods(scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "period"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  def handle_event("set_current", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Actions.run(SetCurrentPeriod, scope, %{"period_id" => id}) do
      {:ok, period} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("%{name} is now the current one.", name: period.name))
         |> assign(periods: Periods.list(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:periods}>
      <.header>
        {term_title(@current_scope, :period, 2)}
        <:subtitle>
          {gettext("Mark the current one: it is suggested by default.")}
        </:subtitle>
        <:actions>
          <.button icon="plus" patch={Paths.new_period(@current_scope)}>
            {gettext_term(@current_scope, :period, "New %{term}")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@form} class="mb-6">
        <:header>
          {if @editing,
            do: @editing.name,
            else: gettext_term(@current_scope, :period, "New %{term}")}
        </:header>
        <.form for={@form} id="period_form" phx-submit="save">
          <.input
            field={@form[:name]}
            label={gettext("Name")}
            placeholder={gettext("2027 · 1st semester")}
            required
          />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:starts_on]} type="date" label={gettext("Starts on")} required />
            <.input field={@form[:ends_on]} type="date" label={gettext("Ends on")} required />
          </div>
          <.input
            :if={!@editing}
            field={@form[:current]}
            type="checkbox"
            label={gettext_term(@current_scope, :period, "Mark as the current %{term}")}
          />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button variant="ghost" patch={Paths.periods(@current_scope)}>
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>
      </.card>

      <.empty_state
        :if={@periods == []}
        icon="calendar-check"
        title={gettext_term(@current_scope, :period, "There are no %{terms} yet")}
      >
        {gettext("Create the first one, for example the semester that is about to start.")}
      </.empty_state>

      <.table :if={@periods != []} id="periods" rows={@periods} row_id={&"period-#{&1.id}"}>
        <:col :let={period} label={gettext("Name")}>
          <span class="font-semibold">{period.name}</span>
          <.badge :if={period.current} family="chilca" class="ms-2">{gettext("Current")}</.badge>
        </:col>
        <:col :let={period} label={gettext("Dates")}>
          {Format.day(period.starts_on)} – {Format.day(period.ends_on)}
        </:col>
        <:action :let={period}>
          <.icon_button
            :if={!period.current}
            icon="star"
            label={gettext("Mark as current")}
            size="sm"
            phx-click="set_current"
            phx-value-id={period.id}
          />
          <.icon_button
            icon="pencil-simple"
            label={gettext("Edit")}
            size="sm"
            phx-click={JS.patch(Paths.edit_period(@current_scope, period))}
          />
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
