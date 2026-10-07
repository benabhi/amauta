defmodule AmautaWeb.NotificationsLive do
  @moduledoc """
  Centro de notificaciones (RF-NOT-001 y 002): las de la persona, de la
  más reciente a la más vieja, con las no leídas resaltadas. Se filtra por
  curso, por tipo y por no leídas; «Marcar todo como leído» respeta los
  filtros. Cada notificación dice qué pasó, dónde, cuándo y por qué le
  llega, con el enlace al ajuste que la controla. Se actualiza en tiempo
  real (`AmautaWeb.NotificationsHook`).
  """
  use AmautaWeb, :live_view

  alias Amauta.Notifications
  alias Amauta.Notifications.{Catalog, Message}
  alias AmautaWeb.{Format, Paths}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: gettext("Notifications"),
       courses: Notifications.courses(scope),
       timezone: scope.user.timezone || scope.institution.timezone
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = Map.take(params, ~w(course event unread page))
    {:noreply, socket |> assign(filters: filters) |> load()}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    page = Notifications.list(scope, socket.assigns.filters)
    assign(socket, page: page, unread: Notifications.unread_count(scope))
  end

  @impl true
  def handle_info({:notifications, :changed}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(~w(course event))
      |> Map.merge(Map.take(socket.assigns.filters, ["unread"]))
      |> Enum.reject(fn {_key, value} -> value in ["", "false"] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: Paths.notifications(socket.assigns.current_scope, filters))}
  end

  def handle_event("open", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Notifications.mark_read(scope, id) do
      {:ok, notification} ->
        notification = Amauta.Repo.preload(notification, :course, Amauta.Tenancy.opts(scope))
        {:noreply, push_navigate(socket, to: Paths.notification_target(scope, notification))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("read_all", _params, socket) do
    {:ok, _} = Notifications.mark_all_read(socket.assigns.current_scope, socket.assigns.filters)
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("Notifications")}
        <:subtitle>
          {if @unread > 0,
            do: ngettext("%{count} unread", "%{count} unread", @unread),
            else: gettext("You are up to date")}
        </:subtitle>
        <:actions>
          <.button
            :if={@unread > 0}
            id="notifications-read-all"
            variant="secondary"
            icon="check"
            phx-click="read_all"
          >
            {gettext("Mark all as read")}
          </.button>
          <.button
            id="notifications-preferences"
            variant="ghost"
            icon="gear"
            navigate={Paths.notification_settings(@current_scope)}
          >
            {gettext("Preferences")}
          </.button>
        </:actions>
      </.header>

      <%!-- Una sola barra: qué mostrar, filtros y, si hay algo sin leer, marcarlo. --%>
      <div class="mb-4 flex flex-wrap items-center gap-3 rounded-card border border-line bg-surface p-2 shadow-sm">
        <div
          id="notifications-unread-filter"
          role="group"
          aria-label={gettext("Show")}
          class="inline-flex rounded-control bg-surface-sunken p-1"
        >
          <.link
            :for={{value, label} <- [{nil, gettext("All")}, {"true", gettext("Unread")}]}
            patch={Paths.notifications(@current_scope, unread_filters(@filters, value))}
            aria-current={if @filters["unread"] == value, do: "true"}
            class={[
              "inline-flex min-h-9 items-center gap-1.5 rounded-control px-3 text-sm font-semibold transition-colors duration-fast",
              if(@filters["unread"] == value,
                do: "bg-surface text-ink shadow-sm",
                else: "text-ink-muted hover:text-ink"
              )
            ]}
          >
            {label}
            <span
              :if={value == "true" and @unread > 0}
              class="rounded-full bg-primary px-1.5 text-xs leading-5 text-on-primary"
            >
              {@unread}
            </span>
          </.link>
        </div>

        <.form
          for={%{}}
          id="notifications-filters"
          phx-change="filter"
          class="flex flex-wrap gap-2 [&>div>div]:mb-0"
        >
          <div :if={@courses != []} class="w-56">
            <.input
              name="course"
              type="select"
              value={@filters["course"]}
              prompt={gettext_term(@current_scope, :course, "All %{terms}")}
              options={Enum.map(@courses, &{&1.name, &1.id})}
              aria-label={term_title(@current_scope, :course)}
            />
          </div>
          <div class="w-60">
            <.input
              name="event"
              type="select"
              value={@filters["event"]}
              prompt={gettext("All types")}
              options={Enum.map(Catalog.events(), &{Catalog.label(&1), &1})}
              aria-label={gettext("Type")}
            />
          </div>
        </.form>
      </div>

      <.empty_state
        :if={@page.entries == []}
        icon="bell"
        title={gettext("You are up to date")}
      >
        {gettext_term(
          @current_scope,
          :course,
          "When something happens in your %{terms}, it will appear here."
        )}
      </.empty_state>

      <ul
        :if={@page.entries != []}
        id="notifications"
        class="overflow-hidden rounded-card border border-line bg-surface shadow-sm"
      >
        <li
          :for={n <- @page.entries}
          id={"notification-#{n.id}"}
          class={[
            "border-t border-line first:border-t-0",
            is_nil(n.read_at) && "bg-anil-soft/40"
          ]}
        >
          <div class="flex items-start gap-3 px-4 py-3">
            <span
              class={[
                "mt-2 size-2 shrink-0 rounded-full",
                if(is_nil(n.read_at), do: "bg-primary", else: "bg-transparent")
              ]}
              aria-hidden="true"
            />
            <.icon name={event_icon(n.event)} class="mt-0.5 size-5 shrink-0 text-ink-muted" />
            <div class="min-w-0 flex-1">
              <button
                type="button"
                phx-click="open"
                phx-value-id={n.id}
                class={[
                  "text-start hover:underline focus-visible:outline-2 focus-visible:outline-primary",
                  is_nil(n.read_at) && "font-semibold"
                ]}
              >
                {Message.text(n)}
                <span :if={is_nil(n.read_at)} class="sr-only">{gettext("(unread)")}</span>
              </button>
              <p class="mt-0.5 flex flex-wrap items-center gap-x-2 text-sm text-ink-muted">
                <span :if={n.course}>{where(@current_scope, n)}</span>
                <time datetime={DateTime.to_iso8601(n.updated_at)}>
                  · {Format.datetime(n.updated_at, @timezone, :short)}
                </time>
              </p>
              <p class="mt-1 text-xs text-ink-muted">
                {Message.reason(n)}
                <.link
                  navigate={Paths.notification_settings(@current_scope)}
                  class="font-semibold underline hover:text-ink"
                >
                  {gettext("Adjust")}
                </.link>
              </p>
            </div>
          </div>
        </li>
      </ul>

      <nav
        :if={@page.page > 1 or @page.more}
        class="mt-4 flex justify-between"
        aria-label={gettext("Pagination")}
      >
        <.button
          :if={@page.page > 1}
          variant="secondary"
          size="sm"
          icon="arrow-left"
          patch={Paths.notifications(@current_scope, Map.put(@filters, "page", @page.page - 1))}
        >
          {gettext("Previous")}
        </.button>
        <span></span>
        <.button
          :if={@page.more}
          variant="secondary"
          size="sm"
          patch={Paths.notifications(@current_scope, Map.put(@filters, "page", @page.page + 1))}
        >
          {gettext("Next")}
        </.button>
      </nav>
    </Layouts.app>
    """
  end

  defp unread_filters(filters, nil), do: filters |> Map.delete("unread") |> Map.delete("page")

  defp unread_filters(filters, value),
    do: filters |> Map.put("unread", value) |> Map.delete("page")

  # Dónde pasó: Institución › Trayecto › Curso (RF-NOT-002).
  defp where(scope, %{course: course}) do
    [
      scope.institution.short_name || scope.institution.name,
      course.pathway && course.pathway.name,
      course.name
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" › ")
  end

  defp event_icon("feed.mentioned"), do: "at"
  defp event_icon("feed.reply_created"), do: "chats-circle"
  defp event_icon("feed.post_published"), do: "chats-circle"
  defp event_icon("content.item_published"), do: "book-open"
  defp event_icon("enrollment.created"), do: "graduation-cap"
  defp event_icon(_event), do: "bell"
end
