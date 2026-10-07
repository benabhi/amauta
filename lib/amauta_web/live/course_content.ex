defmodule AmautaWeb.CourseContent do
  @moduledoc """
  Pestaña Contenido del curso (RF-CON-001, 002, 004 y 005): las unidades,
  plegables, con sus elementos adentro.

  Quien gestiona el contenido crea y edita unidades acá mismo, agrega
  páginas y materiales (que se editan en `AmautaWeb.ContentItemLive`), los
  oculta o programa y los ordena: arrastrando (mouse o dedo, también de una
  unidad a otra) o con «Subir» y «Bajar» de cada menú (teclado).
  """
  use AmautaWeb, :live_component

  import AmautaWeb.ContentComponents

  alias Amauta.{Actions, Content}

  alias Amauta.Content.Actions.{
    CreateUnit,
    DeleteItem,
    DeleteUnit,
    MoveItem,
    MoveUnit,
    UpdateItem,
    UpdateUnit
  }

  alias AmautaWeb.Paths

  @impl true
  def mount(socket), do: {:ok, assign(socket, unit_form: nil, editing_unit: nil)}

  @impl true
  def update(assigns, socket) do
    %{current_scope: scope, course: course} = assigns

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       can_manage: Content.can_manage?(scope, course),
       tracks: Content.tracks_progress?(scope, course),
       timezone: scope.user.timezone || scope.institution.timezone
     )
     |> load()}
  end

  defp load(socket) do
    %{current_scope: scope, course: course} = socket.assigns

    assign(socket,
      units: Content.list_units(scope, course),
      done: Content.completed_ids(scope, course)
    )
  end

  ## Unidades

  @impl true
  def handle_event("new_unit", _params, socket) do
    form = build_unit_form(%{"visibility" => "visible"})
    {:noreply, assign(socket, unit_form: form, editing_unit: :new)}
  end

  def handle_event("edit_unit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.units, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      unit ->
        form =
          build_unit_form(%{
            "title" => unit.title,
            "description" => unit.description,
            "starts_on" => unit.starts_on,
            "ends_on" => unit.ends_on,
            "visibility" => unit.visibility,
            "publish_local" => to_local(unit.publish_at, socket.assigns.timezone)
          })

        {:noreply, assign(socket, unit_form: form, editing_unit: unit.id)}
    end
  end

  def handle_event("cancel_unit", _params, socket),
    do: {:noreply, assign(socket, unit_form: nil, editing_unit: nil)}

  # Para mostrar u ocultar la fecha de publicación según la visibilidad.
  def handle_event("change_unit", %{"unit" => params}, socket),
    do: {:noreply, assign(socket, unit_form: build_unit_form(params))}

  def handle_event("save_unit", %{"unit" => params}, socket) do
    %{current_scope: scope, course: course, editing_unit: editing, timezone: tz} = socket.assigns
    input = visibility_params(params, tz)

    result =
      case editing do
        :new -> Actions.run(CreateUnit, scope, Map.put(input, "course_id", course.id))
        id -> Actions.run(UpdateUnit, scope, Map.put(input, "unit_id", id))
      end

    case result do
      {:ok, _unit} ->
        {:noreply, socket |> assign(unit_form: nil, editing_unit: nil) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, unit_form: build_unit_form(params, changeset.errors))}

      {:error, _} ->
        {:noreply, flash_error(socket)}
    end
  end

  def handle_event("toggle_unit", %{"id" => id, "visibility" => visibility}, socket) do
    params = %{"unit_id" => id, "visibility" => visibility}
    run(socket, UpdateUnit, params)
  end

  def handle_event("move_unit", %{"id" => id, "dir" => dir}, socket) do
    index = Enum.find_index(socket.assigns.units, &(&1.id == id))
    run(socket, MoveUnit, %{"unit_id" => id, "index" => step(index, dir)})
  end

  def handle_event("delete_unit", %{"id" => id}, socket),
    do: run(socket, DeleteUnit, %{"unit_id" => id})

  ## Elementos

  def handle_event("toggle_item", %{"id" => id, "visibility" => visibility}, socket),
    do: run(socket, UpdateItem, %{"item_id" => id, "visibility" => visibility})

  def handle_event("move_item", %{"id" => id, "dir" => dir}, socket) do
    unit = Enum.find(socket.assigns.units, fn u -> Enum.any?(u.items, &(&1.id == id)) end)
    index = Enum.find_index(unit.items, &(&1.id == id))
    run(socket, MoveItem, %{"item_id" => id, "unit_id" => unit.id, "index" => step(index, dir)})
  end

  def handle_event("delete_item", %{"id" => id}, socket),
    do: run(socket, DeleteItem, %{"item_id" => id})

  # Lo soltado al arrastrar (hook .ContentSort).
  def handle_event("drop", %{"type" => "unit", "id" => id, "index" => index}, socket),
    do: run(socket, MoveUnit, %{"unit_id" => id, "index" => index})

  def handle_event(
        "drop",
        %{"type" => "item", "id" => id, "unit" => unit, "index" => index},
        socket
      ),
      do: run(socket, MoveItem, %{"item_id" => id, "unit_id" => unit, "index" => index})

  defp step(index, "up"), do: index - 1
  defp step(index, "down"), do: index + 1

  defp run(socket, action, params) do
    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, _} -> {:noreply, socket |> flash_error() |> load()}
    end
  end

  # Los avisos los muestra la vista del curso.
  defp flash_error(socket) do
    send(self(), {:put_flash, :error, gettext("That could not be done.")})
    socket
  end

  # El formulario trabaja con la fecha local (`publish_local`); el error de
  # `publish_at` se muestra en ese campo.
  defp build_unit_form(params, errors \\ []) do
    errors =
      Enum.map(errors, fn
        {:publish_at, error} -> {:publish_local, error}
        other -> other
      end)

    to_form(params, as: "unit", errors: errors, action: if(errors != [], do: :validate))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook=".ContentSort" phx-target={@myself} class="grid gap-4">
      <div :if={@can_manage and @editing_unit != :new} class="flex justify-end">
        <.button id="content-new-unit" icon="plus" phx-click="new_unit" phx-target={@myself}>
          {gettext_term(@current_scope, :unit, "New %{term}")}
        </.button>
      </div>

      <.unit_form
        :if={@editing_unit == :new}
        id="unit-form-new"
        form={@unit_form}
        timezone={@timezone}
        title={gettext_term(@current_scope, :unit, "New %{term}")}
        myself={@myself}
      />

      <.empty_state
        :if={@units == [] and @editing_unit != :new}
        icon="book-open"
        title={gettext("There is no content yet")}
      >
        {gettext_term(
          @current_scope,
          :unit,
          "Content is organized in %{terms}, with pages, materials and assignments."
        )}
      </.empty_state>

      <ol :if={@units != []} id="content-units" class="grid gap-3" data-sort-units>
        <li
          :for={{unit, index} <- Enum.with_index(@units)}
          id={"unit-#{unit.id}"}
          data-sort-unit
          data-id={unit.id}
        >
          <.unit_form
            :if={@editing_unit == unit.id}
            id={"unit-form-#{unit.id}"}
            form={@unit_form}
            timezone={@timezone}
            title={gettext_term(@current_scope, :unit, "Edit %{term}")}
            myself={@myself}
          />
          <.unit
            :if={@editing_unit != unit.id}
            unit={unit}
            done={@done}
            tracks={@tracks}
            first={index == 0}
            last={index == length(@units) - 1}
            can_manage={@can_manage}
            current_scope={@current_scope}
            course={@course}
            timezone={@timezone}
            myself={@myself}
          />
        </li>
      </ol>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ContentSort">
        // Ordenar arrastrando (RF-CON-001 y 004): unidades entre sí, y
        // elementos dentro de su unidad o hacia otra. Se arrastra desde la
        // manija; con teclado, «Subir» y «Bajar» de cada menú.
        export default {
          mounted() {
            this.onStart = (e) => {
              const handle = e.target.closest?.("[data-drag-handle]")
              if (!handle || !this.el.contains(handle)) return
              const item = handle.closest("[data-sort-item]")
              const unit = handle.closest("[data-sort-unit]")
              this.drag = item ? {type: "item", el: item} : {type: "unit", el: unit}
              e.dataTransfer.effectAllowed = "move"
              e.dataTransfer.setData("text/plain", this.drag.el.dataset.id)
              e.dataTransfer.setDragImage(this.drag.el, 24, 24)
              this.drag.el.dataset.dragging = ""
            }
            this.onEnd = () => {
              if (this.drag) delete this.drag.el.dataset.dragging
              this.drag = null
            }
            // Posición entre los hermanos según la altura del puntero.
            this.indexIn = (list, selector, y) => {
              const others = [...list.querySelectorAll(`:scope > ${selector}`)].filter((x) => x !== this.drag.el)
              const before = others.findIndex((x) => {
                const r = x.getBoundingClientRect()
                return y < r.top + r.height / 2
              })
              return before === -1 ? others.length : before
            }
            this.el.addEventListener("dragover", (e) => { if (this.drag) e.preventDefault() })
            this.el.addEventListener("drop", (e) => {
              if (!this.drag) return
              e.preventDefault()
              const id = this.drag.el.dataset.id
              if (this.drag.type === "unit") {
                const list = this.el.querySelector("[data-sort-units]")
                this.pushEventTo(this.el, "drop", {type: "unit", id, index: this.indexIn(list, "[data-sort-unit]", e.clientY)})
              } else {
                const unit = e.target.closest("[data-sort-unit]")
                const list = unit?.querySelector("[data-unit-items]")
                if (list) {
                  const index = this.indexIn(list, "[data-sort-item]", e.clientY)
                  this.pushEventTo(this.el, "drop", {type: "item", id, unit: unit.dataset.id, index})
                }
              }
              this.onEnd()
            })
            document.addEventListener("dragstart", this.onStart)
            document.addEventListener("dragend", this.onEnd)
          },
          destroyed() {
            document.removeEventListener("dragstart", this.onStart)
            document.removeEventListener("dragend", this.onEnd)
          }
        }
      </script>
    </div>
    """
  end

  attr :unit, :map, required: true
  attr :first, :boolean, required: true
  attr :done, :any, required: true, doc: "IDs de los elementos hechos (MapSet)"
  attr :tracks, :boolean, required: true
  attr :last, :boolean, required: true
  attr :can_manage, :boolean, required: true
  attr :current_scope, :map, required: true
  attr :course, :map, required: true
  attr :timezone, :string, required: true
  attr :myself, :any, required: true

  # Una unidad: el encabezado pliega y despliega sus elementos (en el
  # navegador, sin ir al servidor).
  defp unit(assigns) do
    %{unit: unit, tracks: tracks, done: done} = assigns
    progress = if tracks and unit.items != [], do: Content.unit_progress(unit, done)

    assigns =
      assign(assigns,
        body_id: "unit-body-#{unit.id}",
        progress: progress,
        progress_label: progress && progress_label(progress)
      )

    ~H"""
    <section class="rounded-card border border-line bg-surface shadow-sm in-data-dragging:opacity-60">
      <header class="flex items-center gap-2 px-3 py-2">
        <span
          :if={@can_manage}
          data-drag-handle
          draggable="true"
          aria-hidden="true"
          title={gettext("Drag to reorder")}
          class="hidden cursor-grab text-ink-muted hover:text-ink md:block"
        >
          <.icon name="dots-six-vertical" class="size-5" />
        </span>
        <button
          type="button"
          id={"unit-toggle-#{@unit.id}"}
          aria-expanded="true"
          aria-controls={@body_id}
          phx-click={
            JS.toggle_attribute({"aria-expanded", "true", "false"})
            |> JS.toggle_class("hidden", to: "##{@body_id}")
          }
          class="group flex min-h-11 min-w-0 flex-1 items-center gap-2 rounded-control px-1 text-start focus-visible:outline-2 focus-visible:outline-primary"
        >
          <.icon
            name="caret-right"
            class="size-4 shrink-0 text-ink-muted transition-transform duration-fast group-aria-expanded:rotate-90"
          />
          <span class="min-w-0">
            <span class="block truncate font-semibold">{@unit.title}</span>
            <span class="block text-sm text-ink-muted">
              {if @progress,
                do: @progress_label,
                else: ngettext("%{count} item", "%{count} items", length(@unit.items))}
              <span :if={dates(@unit)}>· {dates(@unit)}</span>
            </span>
          </span>
        </button>
        <.progress_bar
          :if={@progress}
          value={elem(@progress, 0)}
          max={elem(@progress, 1)}
          label={@progress_label}
          class="hidden w-24 shrink-0 sm:block"
        />
        <.visibility_badge subject={@unit} timezone={@timezone} />
        <.dropdown
          :if={@can_manage}
          id={"unit-menu-#{@unit.id}"}
          label={gettext_term(@current_scope, :unit, "%{term} options")}
        >
          <:trigger><.icon name="dots-three" class="size-5 text-ink-muted" /></:trigger>
          <.dropdown_item
            icon="pencil-simple"
            phx-click="edit_unit"
            phx-value-id={@unit.id}
            phx-target={@myself}
          >
            {gettext("Edit")}
          </.dropdown_item>
          <.dropdown_item
            icon={if @unit.visibility == "visible", do: "eye-slash", else: "eye"}
            phx-click="toggle_unit"
            phx-value-id={@unit.id}
            phx-value-visibility={if @unit.visibility == "visible", do: "hidden", else: "visible"}
            phx-target={@myself}
          >
            {if @unit.visibility == "visible",
              do: gettext("Hide from students"),
              else: gettext("Show to students")}
          </.dropdown_item>
          <.dropdown_item
            :if={!@first}
            icon="arrow-up"
            phx-click="move_unit"
            phx-value-id={@unit.id}
            phx-value-dir="up"
            phx-target={@myself}
          >
            {gettext("Move up")}
          </.dropdown_item>
          <.dropdown_item
            :if={!@last}
            icon="arrow-down"
            phx-click="move_unit"
            phx-value-id={@unit.id}
            phx-value-dir="down"
            phx-target={@myself}
          >
            {gettext("Move down")}
          </.dropdown_item>
          <.dropdown_item
            icon="trash"
            phx-click="delete_unit"
            phx-value-id={@unit.id}
            phx-target={@myself}
            data-confirm={
              gettext_term(@current_scope, :unit, "Delete this %{term} and everything in it?")
            }
          >
            {gettext("Delete")}
          </.dropdown_item>
        </.dropdown>
      </header>

      <div id={@body_id}>
        <p :if={@unit.description} class="px-4 pb-3 text-sm text-ink-muted whitespace-pre-line">
          {@unit.description}
        </p>

        <ol
          id={"unit-items-#{@unit.id}"}
          data-unit-items
          class={["min-h-2", @unit.items != [] && "border-t border-line"]}
        >
          <.item
            :for={{item, index} <- Enum.with_index(@unit.items)}
            item={item}
            done={MapSet.member?(@done, item.id)}
            first={index == 0}
            last={index == length(@unit.items) - 1}
            can_manage={@can_manage}
            current_scope={@current_scope}
            course={@course}
            timezone={@timezone}
            myself={@myself}
          />
        </ol>

        <div :if={@can_manage} class="flex flex-wrap gap-2 border-t border-line px-3 py-2">
          <.button
            variant="ghost"
            size="sm"
            icon="file-text"
            navigate={Paths.new_course_item(@current_scope, @course, @unit, "page")}
          >
            {gettext("Add page")}
          </.button>
          <.button
            variant="ghost"
            size="sm"
            icon="paperclip"
            navigate={Paths.new_course_item(@current_scope, @course, @unit, "material")}
          >
            {gettext("Add material")}
          </.button>
        </div>
      </div>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :first, :boolean, required: true
  attr :done, :boolean, default: false
  attr :last, :boolean, required: true
  attr :can_manage, :boolean, required: true
  attr :current_scope, :map, required: true
  attr :course, :map, required: true
  attr :timezone, :string, required: true
  attr :myself, :any, required: true

  defp item(assigns) do
    ~H"""
    <li
      id={"item-#{@item.id}"}
      data-sort-item
      data-id={@item.id}
      class="flex items-center gap-3 border-t border-line px-3 py-2 first:border-t-0 data-dragging:opacity-50"
    >
      <span
        :if={@can_manage}
        data-drag-handle
        draggable="true"
        aria-hidden="true"
        title={gettext("Drag to reorder")}
        class="hidden cursor-grab text-ink-muted hover:text-ink md:block"
      >
        <.icon name="dots-six-vertical" class="size-5" />
      </span>
      <.kind_icon kind={@item.kind} />
      <.link
        navigate={Paths.course_item(@current_scope, @course, @item)}
        class={[
          "min-w-0 flex-1 truncate py-2 font-medium hover:underline",
          @item.visibility != "visible" && "text-ink-muted"
        ]}
      >
        {@item.title}
      </.link>
      <.visibility_badge subject={@item} timezone={@timezone} />
      <span :if={@done} class="shrink-0 text-chilca-deep" title={gettext("Completed")}>
        <.icon name="check-circle" class="size-5" />
        <span class="sr-only">{gettext("Completed")}</span>
      </span>
      <.dropdown :if={@can_manage} id={"item-menu-#{@item.id}"} label={gettext("Item options")}>
        <:trigger><.icon name="dots-three" class="size-5 text-ink-muted" /></:trigger>
        <.dropdown_item
          icon="pencil-simple"
          navigate={Paths.edit_course_item(@current_scope, @course, @item)}
        >
          {gettext("Edit")}
        </.dropdown_item>
        <.dropdown_item
          icon={if @item.visibility == "visible", do: "eye-slash", else: "eye"}
          phx-click="toggle_item"
          phx-value-id={@item.id}
          phx-value-visibility={if @item.visibility == "visible", do: "hidden", else: "visible"}
          phx-target={@myself}
        >
          {if @item.visibility == "visible",
            do: gettext("Hide from students"),
            else: gettext("Show to students")}
        </.dropdown_item>
        <.dropdown_item
          :if={!@first}
          icon="arrow-up"
          phx-click="move_item"
          phx-value-id={@item.id}
          phx-value-dir="up"
          phx-target={@myself}
        >
          {gettext("Move up")}
        </.dropdown_item>
        <.dropdown_item
          :if={!@last}
          icon="arrow-down"
          phx-click="move_item"
          phx-value-id={@item.id}
          phx-value-dir="down"
          phx-target={@myself}
        >
          {gettext("Move down")}
        </.dropdown_item>
        <.dropdown_item
          icon="trash"
          phx-click="delete_item"
          phx-value-id={@item.id}
          phx-target={@myself}
          data-confirm={gettext("Delete «%{title}»?", title: @item.title)}
        >
          {gettext("Delete")}
        </.dropdown_item>
      </.dropdown>
    </li>
    """
  end

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :timezone, :string, required: true
  attr :title, :string, required: true
  attr :myself, :any, required: true

  defp unit_form(assigns) do
    ~H"""
    <.card id={"#{@id}-card"}>
      <:header>{@title}</:header>
      <.form
        for={@form}
        id={@id}
        phx-change="change_unit"
        phx-submit="save_unit"
        phx-target={@myself}
      >
        <.input field={@form[:title]} label={gettext("Title")} required />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input field={@form[:starts_on]} type="date" label={gettext("Starts on (optional)")} />
          <.input field={@form[:ends_on]} type="date" label={gettext("Ends on (optional)")} />
        </div>
        <.visibility_fields form={@form} timezone={@timezone} />
        <div class="flex gap-2">
          <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
          <.button type="button" variant="ghost" phx-click="cancel_unit" phx-target={@myself}>
            {gettext("Cancel")}
          </.button>
        </div>
      </.form>
    </.card>
    """
  end

  defp progress_label({done, total}),
    do: ngettext("%{done} of %{count} done", "%{done} of %{count} done", total, done: done)

  # «del 1/3 al 15/3», «desde el 1/3» o «hasta el 15/3».
  defp dates(%{starts_on: nil, ends_on: nil}), do: nil

  defp dates(%{starts_on: from, ends_on: nil}),
    do: gettext("from %{date}", date: AmautaWeb.Format.day(from, :short))

  defp dates(%{starts_on: nil, ends_on: to}),
    do: gettext("until %{date}", date: AmautaWeb.Format.day(to, :short))

  defp dates(%{starts_on: from, ends_on: to}),
    do:
      gettext("%{from} to %{to}",
        from: AmautaWeb.Format.day(from, :short),
        to: AmautaWeb.Format.day(to, :short)
      )
end
