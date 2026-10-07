defmodule AmautaWeb.NotificationsHook do
  @moduledoc """
  Notificaciones en tiempo real en todas las pantallas (RF-NOT-001): se
  suscribe a las de la persona y, cuando cambian, actualiza la campana de
  la barra superior (`AmautaWeb.Components.NotificationBell`). La pantalla
  del centro de notificaciones recibe además el mensaje para recargarse.
  """
  import Phoenix.LiveView

  alias Amauta.Notifications

  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns[:current_scope]

    if (connected?(socket) and scope) && scope.user do
      Notifications.subscribe(scope)
      {:cont, attach_hook(socket, :notifications, :handle_info, &handle_info/2)}
    else
      {:cont, socket}
    end
  end

  defp handle_info({:notifications, :changed}, socket) do
    send_update(AmautaWeb.Components.NotificationBell, id: "notification-bell", refresh: true)

    # El centro de notificaciones también lo recibe, para recargar la lista.
    if socket.view == AmautaWeb.NotificationsLive,
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
