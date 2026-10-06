defmodule AmautaWeb.Layouts do
  @moduledoc """
  Layouts de la aplicación: el raíz (`root.html.heex`) y el de las
  pantallas (`app/1`), con la barra superior de la institución.
  """
  use AmautaWeb, :html

  alias Amauta.Accounts.User
  alias AmautaWeb.Paths

  embed_templates "layouts/*"

  @doc """
  Layout de las pantallas: barra superior con la institución, el selector de
  tema y el menú de la persona, y el contenido centrado.

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Contenido</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil, doc: "el Amauta.Scope de la pantalla"
  attr :width, :string, default: "md", values: ~w(sm md lg), doc: "ancho del contenido"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a
      href="#main"
      class="sr-only focus:not-sr-only focus:fixed focus:start-4 focus:top-4 focus:z-50 focus:rounded-control focus:bg-surface focus:px-3 focus:py-2"
    >
      {gettext("Skip to content")}
    </a>

    <header class="sticky top-0 z-40 border-b border-line bg-paper/85 backdrop-blur">
      <div class="mx-auto flex h-14 max-w-6xl items-center gap-4 px-4 sm:px-6">
        <.brand current_scope={@current_scope} />
        <div class="ms-auto flex items-center gap-2">
          <.theme_toggle />
          <.user_menu :if={@current_scope && @current_scope.user} current_scope={@current_scope} />
        </div>
      </div>
    </header>

    <main id="main" class="px-4 py-10 sm:px-6">
      <div class={["mx-auto", content_width(@width)]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  defp content_width("sm"), do: "max-w-sm"
  defp content_width("md"), do: "max-w-3xl"
  defp content_width("lg"), do: "max-w-6xl"

  attr :current_scope, :map, default: nil

  defp brand(assigns) do
    ~H"""
    <.link
      href={if @current_scope, do: Paths.home(@current_scope), else: "/"}
      class="flex min-w-0 items-center gap-2.5 rounded-control"
    >
      <span class="flex size-8 shrink-0 items-center justify-center rounded-control bg-anil-soft text-anil-deep">
        <.icon name="graduation-cap" class="size-5" />
      </span>
      <span class="truncate font-display text-lg font-semibold">
        {if @current_scope,
          do: @current_scope.institution.short_name || @current_scope.institution.name,
          else: "Amauta"}
      </span>
    </.link>
    """
  end

  attr :current_scope, :map, required: true

  defp user_menu(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <.link
        navigate={Paths.settings(@current_scope)}
        class="flex items-center gap-2 rounded-control px-2 py-1 hover:bg-surface-sunken"
        title={gettext("Settings")}
      >
        <.avatar name={User.display_name(@current_scope.user)} size="sm" />
        <span class="hidden text-sm sm:inline">{@current_scope.user.first_name}</span>
      </.link>
      <.link
        href={Paths.log_out(@current_scope)}
        method="delete"
        class="flex size-9 items-center justify-center rounded-control text-ink-muted hover:bg-surface-sunken hover:text-ink"
        aria-label={gettext("Log out")}
        title={gettext("Log out")}
      >
        <.icon name="sign-out" class="size-5" />
      </.link>
    </div>
    """
  end

  @doc "Avisos flash y de conexión."
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>
    </div>
    """
  end

  @doc """
  Selector de tema: sistema, claro u oscuro. El script de `root.html.heex`
  lo aplica y lo recuerda en el navegador.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      class="relative flex items-center rounded-full border border-line bg-surface-sunken p-0.5"
      role="group"
      aria-label={gettext("Color theme")}
    >
      <div class={[
        "absolute h-7 w-7 rounded-full bg-surface shadow-sm transition-[inset-inline-start] duration-base ease-standard",
        "start-0.5 [[data-theme-source=user][data-theme=light]_&]:start-[calc(0.125rem+1.75rem)]",
        "[[data-theme-source=user][data-theme=dark]_&]:start-[calc(0.125rem+3.5rem)]"
      ]} />
      <button
        :for={
          {theme, icon, label} <- [
            {"system", "desktop", gettext("System theme")},
            {"light", "sun", gettext("Light theme")},
            {"dark", "moon", gettext("Dark theme")}
          ]
        }
        type="button"
        class="relative flex size-7 cursor-pointer items-center justify-center rounded-full text-ink-muted hover:text-ink"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme={theme}
        aria-label={label}
        title={label}
      >
        <.icon name={icon} class="size-4" />
      </button>
    </div>
    """
  end
end
