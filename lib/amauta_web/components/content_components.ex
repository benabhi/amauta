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
end
