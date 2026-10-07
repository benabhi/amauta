defmodule AmautaWeb.NotificationSettingsLive do
  @moduledoc """
  Preferencias de notificación de la persona (RF-NOT-004 y RF-EML-005,
  parcial: la cascada por institución, trayecto y curso llega en V1): para
  cada evento del catálogo, si llega en Amauta y si llega por email. Sin
  elegir, valen los valores por defecto de la instancia.
  """
  use AmautaWeb, :live_view

  alias Amauta.Notifications
  alias Amauta.Notifications.Catalog
  alias AmautaWeb.Paths

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Notification preferences"))
     |> assign(preferences: Notifications.preferences(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("toggle", %{"event" => event, "channel" => channel}, socket) do
    scope = socket.assigns.current_scope
    enabled = !socket.assigns.preferences[{event, channel}]

    case Notifications.set_preference(scope, event, channel, enabled) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(preferences: Notifications.preferences(scope))
         |> put_flash(:info, gettext("Preferences saved."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("Notification preferences")}
        <:subtitle>
          {gettext("Choose what reaches you in Amauta and what also arrives by email.")}
        </:subtitle>
        <:actions>
          <.button variant="ghost" icon="arrow-left" navigate={Paths.notifications(@current_scope)}>
            {gettext("Notifications")}
          </.button>
        </:actions>
      </.header>

      <div class="overflow-x-auto rounded-card border border-line bg-surface shadow-sm">
        <table id="notification-preferences" class="w-full text-sm">
          <thead>
            <tr class="border-b border-line text-start text-ink-muted">
              <th scope="col" class="px-4 py-3 text-start font-semibold">{gettext("Event")}</th>
              <th
                :for={channel <- Catalog.channels()}
                scope="col"
                class="w-28 px-4 py-3 text-center font-semibold"
              >
                {Catalog.channel_label(channel)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={event <- Catalog.events()} class="border-b border-line last:border-b-0">
              <th scope="row" class="px-4 py-3 text-start font-normal">
                <span class="block font-semibold">{Catalog.label(event)}</span>
                <span class="block text-ink-muted">{Catalog.description(event)}</span>
              </th>
              <td :for={channel <- Catalog.channels()} class="px-4 py-3 text-center">
                <input
                  type="checkbox"
                  id={"pref-#{event}-#{channel}"}
                  checked={@preferences[{event, channel}]}
                  phx-click="toggle"
                  phx-value-event={event}
                  phx-value-channel={channel}
                  aria-label={"#{Catalog.label(event)} · #{Catalog.channel_label(channel)}"}
                  class="size-5 cursor-pointer rounded accent-primary"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-3 text-sm text-ink-muted">
        {gettext(
          "Emails are grouped: if several things happen within a few minutes, they arrive together in one email."
        )}
      </p>
    </Layouts.app>
    """
  end
end
