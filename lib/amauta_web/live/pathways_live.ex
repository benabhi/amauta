defmodule AmautaWeb.PathwaysLive do
  @moduledoc """
  Lista de trayectos (RF-TRA-001) y alta de uno nuevo. Cada persona ve los
  trayectos que puede ver (`Amauta.Pathways.list_visible/2`); crear exige
  `institution.pathways.create`.
  """
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization, Pathways}
  alias Amauta.Pathways.Actions.CreatePathway
  alias Amauta.Pathways.Pathway
  alias AmautaWeb.Paths

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: term_title(scope, :pathway, 2),
       can_create: Authorization.can?(scope, "institution.pathways.create"),
       form: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = Map.take(params, ~w(q status))
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(filters: filters, pathways: Pathways.list_visible(scope, filters))
     |> assign_form(socket.assigns.live_action)}
  end

  defp assign_form(socket, :new) do
    unless socket.assigns.can_create, do: raise(AmautaWeb.ForbiddenError)
    assign(socket, form: to_form(Pathway.changeset(%Pathway{}, %{}), as: "pathway"))
  end

  defp assign_form(socket, _action), do: assign(socket, form: nil)

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params |> Map.take(~w(q status)) |> Enum.reject(fn {_k, v} -> v == "" end) |> Map.new()

    {:noreply, push_patch(socket, to: Paths.pathways(socket.assigns.current_scope, filters))}
  end

  def handle_event("save", %{"pathway" => params}, socket) do
    scope = socket.assigns.current_scope

    case Actions.run(CreatePathway, scope, params) do
      {:ok, pathway} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext_term(scope, :pathway, "The %{term} was created."))
         |> push_navigate(to: Paths.pathway(scope, pathway))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "pathway"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You don't have permission to do that."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:pathways}>
      <.header>
        {term_title(@current_scope, :pathway, 2)}
        <:subtitle>
          {ngettext("%{count} result", "%{count} results", length(@pathways))}
        </:subtitle>
        <:actions>
          <.button :if={@can_create} icon="plus" patch={Paths.new_pathway(@current_scope)}>
            {gettext_term(@current_scope, :pathway, "New %{term}")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@form} class="mb-6">
        <:header>{gettext_term(@current_scope, :pathway, "New %{term}")}</:header>
        <.form for={@form} id="pathway_form" phx-submit="save">
          <AmautaWeb.PathwayLive.fields form={@form} current_scope={@current_scope} />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Create")}</.button>
            <.button variant="ghost" patch={Paths.pathways(@current_scope, @filters)}>
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
            name="status"
            type="select"
            value={@filters["status"]}
            prompt={gettext("Not archived")}
            options={
              Enum.map(
                Pathway.statuses(),
                &{AmautaWeb.PathwayLive.status_label(@current_scope, &1), &1}
              )
            }
            aria-label={gettext("Status")}
          />
        </div>
      </.form>

      <.empty_state
        :if={@pathways == []}
        icon="path"
        title={gettext_term(@current_scope, :pathway, "There are no %{terms} here")}
      >
        {gettext_term(
          @current_scope,
          :pathway,
          "A %{term} groups %{courses} by %{stages}, in order.",
          courses: term(@current_scope, :course, 2),
          stages: term(@current_scope, :stage, 2)
        )}
      </.empty_state>

      <ul :if={@pathways != []} id="pathways" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <li :for={pathway <- @pathways} id={"pathway-#{pathway.id}"}>
          <.tile navigate={Paths.pathway(@current_scope, pathway)} icon="path" title={pathway.name}>
            <:subtitle :if={pathway.code}>{pathway.code}</:subtitle>
            <:badge>
              <AmautaWeb.PathwayLive.status_badge
                status={pathway.status}
                current_scope={@current_scope}
              />
            </:badge>
          </.tile>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
