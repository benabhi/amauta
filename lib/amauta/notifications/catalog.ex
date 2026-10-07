defmodule Amauta.Notifications.Catalog do
  @moduledoc """
  Eventos que notifican en el MVP (RF-NOT-003, Anexo D del ERS), con su
  descripción legible, sus canales y los valores por defecto de la
  instancia (RF-NOT-004, parcial: la cascada por institución, trayecto y
  curso llega en V1).

  Canales: `platform` (el centro de notificaciones, en tiempo real) y
  `email` (agrupado, con baja en un clic).
  """
  use Gettext, backend: AmautaWeb.Gettext

  @channels ~w(platform email)

  # evento => valores por defecto por canal
  @events [
    {"feed.post_published", %{"platform" => true, "email" => true}},
    {"feed.mentioned", %{"platform" => true, "email" => true}},
    {"feed.reply_created", %{"platform" => true, "email" => false}},
    {"content.item_published", %{"platform" => true, "email" => true}},
    {"enrollment.created", %{"platform" => true, "email" => true}}
  ]

  @doc "Canales posibles."
  def channels, do: @channels

  @doc "Eventos del catálogo, en el orden en que se muestran."
  def events, do: Enum.map(@events, &elem(&1, 0))

  @doc "Si el evento existe."
  def event?(event), do: List.keymember?(@events, event, 0)

  @doc "Valor por defecto de la instancia para un evento y un canal."
  def default(event, channel) do
    case List.keyfind(@events, event, 0) do
      {_event, defaults} -> Map.get(defaults, channel, false)
      nil -> false
    end
  end

  @doc "Nombre legible del evento."
  def label("feed.post_published"), do: gettext("New posts in the feed")
  def label("feed.mentioned"), do: gettext("Mentions with «@»")
  def label("feed.reply_created"), do: gettext("Replies to your posts and conversations")
  def label("content.item_published"), do: gettext("New pages and materials")
  def label("enrollment.created"), do: gettext("Your enrollments")

  @doc "Para qué sirve el evento, en una línea."
  def description("feed.post_published"),
    do: gettext("When the teaching team or a classmate posts in a feed you follow.")

  def description("feed.mentioned"),
    do: gettext("When someone mentions you in a post or a reply.")

  def description("feed.reply_created"),
    do: gettext("When someone replies to your post or to a conversation you took part in.")

  def description("content.item_published"),
    do: gettext("When new content becomes available for you.")

  def description("enrollment.created"), do: gettext("When someone enrolls you.")

  def channel_label("platform"), do: gettext("In Amauta")
  def channel_label("email"), do: gettext("Email")
end
