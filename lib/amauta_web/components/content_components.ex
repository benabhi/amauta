defmodule AmautaWeb.ContentComponents do
  @moduledoc """
  Piezas del contenido del curso que comparten el índice
  (`AmautaWeb.CourseContent`) y la página de cada elemento
  (`AmautaWeb.ContentItemLive`): el ícono de cada tipo, la etiqueta de
  visibilidad y los campos para elegirla.
  """
  use AmautaWeb, :html

  alias AmautaWeb.Format

  attr :kind, :string, required: true
  attr :class, :any, default: nil

  @doc "Ícono del tipo de elemento, sobre un fondo de su color."
  def kind_icon(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex size-9 shrink-0 items-center justify-center rounded-control",
        kind_style(@kind),
        @class
      ]}
      aria-hidden="true"
    >
      <.icon name={kind_icon_name(@kind)} class="size-5" />
    </span>
    """
  end

  defp kind_icon_name("page"), do: "file-text"
  defp kind_icon_name("material"), do: "paperclip"

  defp kind_style("page"), do: "bg-anil-soft text-anil-deep"
  defp kind_style("material"), do: "bg-chilca-soft text-chilca-deep"

  @doc "Nombre del tipo de elemento."
  def kind_label("page"), do: gettext("Page")
  def kind_label("material"), do: gettext("Material")

  attr :subject, :map, required: true, doc: "unidad o elemento"
  attr :timezone, :string, required: true

  @doc """
  Etiqueta para lo que el estudiantado no ve: oculto, o programado a
  futuro. Lo visible no lleva etiqueta.
  """
  def visibility_badge(assigns) do
    ~H"""
    <.badge :if={@subject.visibility == "hidden"} family="nogal" icon="eye-slash">
      {gettext("Hidden")}
    </.badge>
    <.badge
      :if={@subject.visibility == "scheduled" and not Amauta.Content.published?(@subject)}
      family="qolle"
      icon="clock"
    >
      {gettext("Published on %{date}",
        date: Format.datetime(@subject.publish_at, @timezone, :short)
      )}
    </.badge>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :timezone, :string, required: true

  @doc """
  Visibilidad (visible, oculta o programada) y, si es programada, la fecha
  y hora de publicación en la zona de la persona.
  """
  def visibility_fields(assigns) do
    ~H"""
    <div class="grid gap-x-4 sm:grid-cols-2">
      <.input
        field={@form[:visibility]}
        type="select"
        label={gettext("Visibility")}
        options={[
          {gettext("Visible"), "visible"},
          {gettext("Hidden from students"), "hidden"},
          {gettext("Scheduled"), "scheduled"}
        ]}
      />
      <.input
        :if={@form[:visibility].value == "scheduled"}
        field={@form[:publish_local]}
        type="datetime-local"
        label={gettext("Publish on")}
        hint={gettext("Time zone: %{zone}", zone: @timezone)}
      />
    </div>
    """
  end

  @doc "Fecha y hora UTC → valor de un campo `datetime-local` en la zona dada."
  def to_local(nil, _timezone), do: nil

  def to_local(%DateTime{} = datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  @doc """
  Valor de un campo `datetime-local` en la zona dada → fecha y hora UTC
  (ISO 8601), o `nil` si está vacío o no es válido.
  """
  def from_local(value, timezone) when is_binary(value) and value != "" do
    value = if String.length(value) == 16, do: value <> ":00", else: value

    with {:ok, naive} <- NaiveDateTime.from_iso8601(value),
         {:ok, datetime} <- local_datetime(naive, timezone) do
      datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()
    else
      _ -> nil
    end
  end

  def from_local(_value, _timezone), do: nil

  # Si la hora no existe o es ambigua (cambio de horario), se toma la
  # primera posible.
  defp local_datetime(naive, timezone) do
    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, _before, just_after} -> {:ok, just_after}
      error -> error
    end
  end

  @doc """
  Parámetros del formulario → los de la acción: la fecha local de
  publicación pasa a `publish_at` (UTC); fuera de «programada», se borra.
  """
  def visibility_params(params, timezone) do
    publish_at =
      if params["visibility"] == "scheduled",
        do: from_local(params["publish_local"], timezone)

    params
    |> Map.delete("publish_local")
    |> Map.put("publish_at", publish_at)
  end

  attr :units, :list, required: true
  attr :current_id, :string, required: true
  attr :done, :any, required: true, doc: "IDs de los elementos hechos (MapSet)"
  attr :tracks, :boolean, required: true
  attr :current_scope, :map, required: true
  attr :course, :map, required: true

  @doc "Índice lateral del curso (RF-CON-007): unidades y elementos, con el actual marcado."
  def content_nav(assigns) do
    ~H"""
    <nav
      id="content-nav"
      aria-label={gettext("Content")}
      class="grid gap-4 text-sm"
    >
      <section :for={unit <- @units} :if={unit.items != []} class="grid gap-1">
        <h2 class="px-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">
          {unit.title}
        </h2>
        <ul class="grid gap-0.5">
          <li :for={item <- unit.items}>
            <.link
              navigate={AmautaWeb.Paths.course_item(@current_scope, @course, item)}
              aria-current={if item.id == @current_id, do: "page"}
              class={[
                "flex min-h-10 items-center gap-2 rounded-control px-2 py-1.5 hover:bg-surface-sunken",
                if(item.id == @current_id,
                  do: "bg-anil-soft font-semibold text-anil-deep",
                  else: "text-ink"
                )
              ]}
            >
              <.icon name={kind_icon_name(item.kind)} class="size-4 shrink-0 text-ink-muted" />
              <span class="min-w-0 flex-1 truncate">{item.title}</span>
              <.icon
                :if={@tracks and MapSet.member?(@done, item.id)}
                name="check-circle"
                class="size-4 shrink-0 text-chilca-deep"
              />
            </.link>
          </li>
        </ul>
      </section>
    </nav>
    """
  end

  @doc "Si el archivo se puede ver integrado en la página (RF-CON-008)."
  def viewable?(%{content_type: "image/" <> _}), do: true
  def viewable?(%{content_type: "application/pdf"}), do: true
  def viewable?(%{content_type: "video/" <> _}), do: true
  def viewable?(%{content_type: "audio/" <> _}), do: true
  def viewable?(_file), do: false

  attr :file, :map, required: true
  attr :tenant, :any, required: true

  @doc """
  Visor integrado (RF-CON-008), con lo que trae el navegador: imágenes,
  PDF, video y audio, sin servicios externos. Arriba, el nombre y la
  descarga.
  """
  def file_viewer(assigns) do
    assigns = assign(assigns, src: AmautaWeb.Paths.file(assigns.tenant, assigns.file.id))

    ~H"""
    <figure
      id={"viewer-#{@file.id}"}
      class="overflow-hidden rounded-card border border-line bg-surface"
    >
      <figcaption class="flex items-center gap-2 border-b border-line px-4 py-2">
        <span class="min-w-0 flex-1 truncate text-sm font-semibold">{@file.filename}</span>
        <span class="text-xs text-ink-muted">{AmautaWeb.Format.bytes(@file.size)}</span>
        <a
          href={AmautaWeb.Paths.file_download(@tenant, @file.id)}
          class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-control text-ink-muted hover:bg-surface-sunken hover:text-ink"
          aria-label={gettext("Download %{name}", name: @file.filename)}
        >
          <.icon name="download-simple" class="size-5" />
        </a>
      </figcaption>
      <div class="bg-surface-sunken">
        <%= case @file.content_type do %>
          <% "image/" <> _ -> %>
            <img
              src={@src}
              alt={@file.filename}
              loading="lazy"
              class="mx-auto max-h-[75vh] object-contain"
            />
          <% "application/pdf" -> %>
            <iframe src={@src} title={@file.filename} class="h-[75vh] w-full" loading="lazy"></iframe>
          <% "video/" <> _ -> %>
            <video src={@src} controls preload="metadata" class="max-h-[75vh] w-full"></video>
          <% "audio/" <> _ -> %>
            <audio src={@src} controls preload="metadata" class="w-full p-4"></audio>
        <% end %>
      </div>
    </figure>
    """
  end
end
