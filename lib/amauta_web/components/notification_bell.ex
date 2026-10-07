defmodule AmautaWeb.Components.NotificationBell do
  @moduledoc """
  Campana de la barra superior (RF-NOT-001): lleva al centro de
  notificaciones y muestra cuántas hay sin leer. La actualiza
  `AmautaWeb.NotificationsHook` en tiempo real.
  """
  use AmautaWeb, :live_component

  alias Amauta.Notifications
  alias AmautaWeb.Paths

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.drop(assigns, [:refresh]))

    {:ok,
     if(assigns[:refresh] || !socket.assigns[:count],
       do: assign(socket, count: Notifications.unread_count(socket.assigns.current_scope)),
       else: socket
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.link
        navigate={Paths.notifications(@current_scope)}
        class="relative inline-flex min-h-11 min-w-11 items-center justify-center rounded-control text-ink-muted hover:bg-surface-sunken hover:text-ink"
        aria-label={
          if @count > 0,
            do: ngettext("Notifications, %{count} unread", "Notifications, %{count} unread", @count),
            else: gettext("Notifications")
        }
      >
        <.icon name="bell" class="size-5" />
        <span
          :if={@count > 0}
          data-unread
          class="absolute end-1.5 top-1.5 inline-flex min-w-4.5 items-center justify-center rounded-full bg-primary px-1 text-[11px] leading-4.5 font-semibold text-on-primary"
        >
          {if @count > 99, do: "99+", else: @count}
        </span>
      </.link>
    </div>
    """
  end
end
