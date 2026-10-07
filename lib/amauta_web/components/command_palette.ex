defmodule AmautaWeb.Components.CommandPalette do
  @moduledoc """
  Paleta de comandos (RF-BUS-001 y RF-UI-003, parciales): con Ctrl+K o ⌘K
  (o el botón de búsqueda, en el celular) se va a cursos, trayectos y
  personas por nombre, y a las acciones básicas. Con «?» muestra la ayuda
  de atajos. Todo con el teclado: ↑ ↓ para moverse, Enter para ir y Esc
  para cerrar.

  Solo muestra lo que la persona puede ver: las búsquedas pasan por las
  mismas consultas que las listas, con sus permisos.

  Va en el layout de las pantallas (`AmautaWeb.Layouts.app/1`), una vez por
  página.
  """
  use AmautaWeb, :live_component

  alias Amauta.Accounts.{Directory, User}
  alias Amauta.{Authorization, Courses, Pathways}
  alias AmautaWeb.Paths

  @limit 5

  @impl true
  def mount(socket), do: {:ok, assign(socket, query: "", groups: [])}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, assign(socket, groups: search(socket.assigns.current_scope, socket.assigns.query))}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    q = String.slice(q, 0, 80)
    {:noreply, assign(socket, query: q, groups: search(socket.assigns.current_scope, q))}
  end

  @doc false
  # Grupos de resultados `{título, [{id, ícono, etiqueta, detalle, ruta}]}`.
  def search(scope, query) do
    q = String.trim(query)

    groups =
      if String.length(q) < 2 do
        [{gettext("Go to"), actions(scope, q)}]
      else
        [
          {gettext("Go to"), actions(scope, q)},
          {term_title(scope, :course, 2), courses(scope, q)},
          {term_title(scope, :pathway, 2), pathways(scope, q)},
          {gettext("People"), people(scope, q)}
        ]
      end

    Enum.reject(groups, fn {_title, items} -> items == [] end)
  end

  defp actions(scope, q) do
    can = &Authorization.can?(scope, &1)

    [
      {"home", "house", gettext("Home"), Paths.home(scope), true},
      {"courses", "book-open", term_title(scope, :course, 2), Paths.courses(scope), true},
      {"pathways", "path", term_title(scope, :pathway, 2), Paths.pathways(scope), true},
      {"people", "users", gettext("People"), Paths.people(scope), can.("institution.users.view")},
      {"periods", "calendar", term_title(scope, :period, 2), Paths.periods(scope),
       can.("institution.periods.manage")},
      {"new-course", "plus", gettext_term(scope, :course, "New %{term}"), Paths.new_course(scope),
       can.("institution.courses.create")},
      {"new-pathway", "plus", gettext_term(scope, :pathway, "New %{term}"),
       Paths.new_pathway(scope), can.("institution.pathways.create")},
      {"join", "key", gettext("Join with a code"), Paths.join(scope), true},
      {"settings", "gear", gettext("Account settings"), Paths.settings(scope), true}
    ]
    |> Enum.filter(fn {_id, _icon, label, _path, allowed} -> allowed and matches?(label, q) end)
    |> Enum.map(fn {id, icon, label, path, _allowed} ->
      {"action-#{id}", icon, label, nil, path}
    end)
  end

  defp courses(scope, q) do
    scope
    |> Courses.list_visible(%{"q" => q})
    |> Enum.filter(&(&1.status != "draft" or Authorization.can?(scope, "course.update", &1)))
    |> Enum.take(@limit)
    |> Enum.map(fn course ->
      detail = course.period && course.period.name
      {"course-#{course.id}", course.icon, course.name, detail, Paths.course(scope, course)}
    end)
  end

  defp pathways(scope, q) do
    scope
    |> Pathways.list_visible(%{"q" => q})
    |> Enum.take(@limit)
    |> Enum.map(fn pathway ->
      {"pathway-#{pathway.id}", "path", pathway.name, pathway.code, Paths.pathway(scope, pathway)}
    end)
  end

  defp people(scope, q) do
    if Authorization.can?(scope, "institution.users.view") do
      scope
      |> Directory.list(%{"q" => q})
      |> Map.fetch!(:entries)
      |> Enum.take(@limit)
      |> Enum.map(fn user ->
        {"person-#{user.id}", "user", User.display_name(user), user.email,
         Paths.people(scope, %{"q" => user.email})}
      end)
    else
      []
    end
  end

  defp matches?(_label, ""), do: true

  defp matches?(label, q) do
    String.contains?(normalize(label), normalize(q))
  end

  defp normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook=".CommandPalette" class="group" data-view="search">
      <div data-overlay class="fixed inset-0 z-50 hidden bg-ink/40 px-4 pt-16 sm:pt-24">
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby={"#{@id}-title"}
          class="mx-auto w-full max-w-xl overflow-hidden rounded-panel border border-line bg-surface shadow-lg"
        >
          <h2 id={"#{@id}-title"} class="sr-only">{gettext("Command palette")}</h2>

          <div class="group-data-[view=help]:hidden">
            <form
              id={"#{@id}-form"}
              phx-change="search"
              phx-submit="search"
              phx-target={@myself}
              class="border-b border-line"
            >
              <label class="flex items-center gap-3 px-4">
                <.icon name="magnifying-glass" class="size-5 text-ink-muted" />
                <input
                  data-input
                  type="text"
                  name="q"
                  value={@query}
                  role="combobox"
                  aria-expanded="true"
                  aria-controls={"#{@id}-results"}
                  aria-autocomplete="list"
                  autocomplete="off"
                  phx-debounce="150"
                  placeholder={gettext("Search or go to…")}
                  aria-label={gettext("Search or go to…")}
                  class="min-h-12 w-full bg-transparent py-3 text-base outline-none placeholder:text-ink-muted"
                />
                <.kbd>Esc</.kbd>
              </label>
            </form>

            <div id={"#{@id}-results"} role="listbox" class="max-h-96 overflow-y-auto p-2">
              <p :if={@groups == []} class="px-3 py-6 text-center text-ink-muted">
                {gettext("Nothing matches «%{query}».", query: @query)}
              </p>
              <div :for={{title, items} <- @groups} class="mb-2 last:mb-0">
                <p class="px-3 py-1 text-xs font-semibold uppercase tracking-wide text-ink-muted">
                  {title}
                </p>
                <.link
                  :for={{id, icon, label, detail, path} <- items}
                  id={"#{@id}-#{id}"}
                  navigate={path}
                  role="option"
                  aria-selected="false"
                  data-result
                  class="flex min-h-11 items-center gap-3 rounded-control px-3 py-2 aria-selected:bg-surface-sunken hover:bg-surface-sunken"
                >
                  <.icon name={icon} class="size-4 text-ink-muted" />
                  <span class="min-w-0 flex-1 truncate">{label}</span>
                  <span :if={detail} class="truncate text-sm text-ink-muted">{detail}</span>
                </.link>
              </div>
            </div>
            <p class="sr-only" aria-live="polite">
              {ngettext(
                "%{count} result",
                "%{count} results",
                Enum.sum_by(@groups, &length(elem(&1, 1)))
              )}
            </p>
          </div>

          <div class="hidden p-5 group-data-[view=help]:block">
            <p class="mb-3 font-semibold">{gettext("Keyboard shortcuts")}</p>
            <dl class="grid grid-cols-[auto_1fr] items-center gap-x-4 gap-y-2 text-sm">
              <dt>
                <.kbd>Ctrl</.kbd>

                <.kbd>K</.kbd>
              </dt>
              <dd>{gettext("Open the command palette")}</dd>
              <dt>
                <.kbd>↑</.kbd>

                <.kbd>↓</.kbd>
              </dt>
              <dd>{gettext("Move between results")}</dd>
              <dt>
                <.kbd>Enter</.kbd>
              </dt>
              <dd>{gettext("Go to the selected result")}</dd>
              <dt>
                <.kbd>Esc</.kbd>
              </dt>
              <dd>{gettext("Close")}</dd>
              <dt>
                <.kbd>?</.kbd>
              </dt>
              <dd>{gettext("Show this help")}</dd>
            </dl>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CommandPalette">
        // Paleta de comandos: abrir, cerrar, moverse con el teclado (RF-UI-003).
        const typing = (el) =>
          el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName))

        export default {
          mounted() {
            this.overlay = this.el.querySelector("[data-overlay]")
            this.active = 0
            this.isOpen = false

            this.onKey = (e) => {
              const open = this.isOpen

              if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
                e.preventDefault()
                open ? this.close() : this.open("search")
              } else if (e.key === "?" && !open && !typing(document.activeElement)) {
                e.preventDefault()
                this.open("help")
              } else if (open && e.key === "Escape") {
                e.preventDefault()
                this.close()
              } else if (open && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
                e.preventDefault()
                this.move(e.key === "ArrowDown" ? 1 : -1)
              } else if (open && e.key === "Enter" && this.el.dataset.view === "search") {
                const item = this.results()[this.active]
                if (item) {
                  e.preventDefault()
                  item.click()
                }
              } else if (open && e.key === "Tab") {
                // Foco atrapado: el buscador y los resultados se recorren con las flechas.
                e.preventDefault()
                this.input().focus()
              }
            }

            this.onOpen = () => this.open("search")
            this.onNavigate = () => this.close()
            this.onClick = (e) => {
              if (e.target === this.overlay) this.close()
            }

            window.addEventListener("keydown", this.onKey)
            window.addEventListener("amauta:palette-open", this.onOpen)
            window.addEventListener("phx:page-loading-start", this.onNavigate)
            this.overlay.addEventListener("click", this.onClick)
          },

          updated() {
            this.active = 0
            this.highlight()
          },

          destroyed() {
            window.removeEventListener("keydown", this.onKey)
            window.removeEventListener("amauta:palette-open", this.onOpen)
            window.removeEventListener("phx:page-loading-start", this.onNavigate)
          },

          input() {
            return this.el.querySelector("[data-input]")
          },

          results() {
            return [...this.el.querySelectorAll("[data-result]")]
          },

          // Con this.js(), los cambios sobreviven a los parches de LiveView.
          open(view) {
            this.js().setAttribute(this.el, "data-view", view)
            this.previous = document.activeElement
            this.js().show(this.overlay)
            this.isOpen = true
            this.active = 0
            this.highlight()
            if (view === "search") {
              // El foco, cuando ya se ve: show() se aplica en el próximo cuadro.
              const focus = () => this.input().focus()
              this.overlay.addEventListener("phx:show-end", focus, {once: true})
              requestAnimationFrame(() => requestAnimationFrame(focus))
            }
          },

          close() {
            if (!this.isOpen) return
            this.js().hide(this.overlay)
            this.isOpen = false
            this.previous?.focus?.()
          },

          move(step) {
            const items = this.results()
            if (items.length === 0) return
            this.active = (this.active + step + items.length) % items.length
            this.highlight()
            items[this.active].scrollIntoView({block: "nearest"})
          },

          highlight() {
            const items = this.results()
            items.forEach((item, i) => item.setAttribute("aria-selected", String(i === this.active)))
            const current = items[this.active]
            const input = this.input()
            if (current) input.setAttribute("aria-activedescendant", current.id)
            else input.removeAttribute("aria-activedescendant")
          }
        }
      </script>
    </div>
    """
  end
end
