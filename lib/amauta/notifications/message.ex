defmodule Amauta.Notifications.Message do
  @moduledoc """
  Textos de una notificación (RF-NOT-002), en el idioma activo: qué pasó
  (`text/1`) y por qué le llega a la persona (`reason/1`). Los usan el
  centro de notificaciones y el email agrupado. La notificación tiene que
  venir con `course` y `actor` cargados.
  """
  use Gettext, backend: AmautaWeb.Gettext

  alias Amauta.Accounts.User
  alias Amauta.Notifications.Notification

  @doc "Qué pasó, en una oración."
  def text(%Notification{event: "feed.post_published"} = n),
    do: gettext("%{actor} posted in %{course}: «%{title}»", vars(n))

  def text(%Notification{event: "feed.mentioned"} = n),
    do: gettext("%{actor} mentioned you in %{course}: «%{title}»", vars(n))

  def text(%Notification{event: "feed.reply_created", count: 1} = n),
    do: gettext("%{actor} replied to «%{title}»", vars(n))

  def text(%Notification{event: "feed.reply_created", count: count} = n),
    do:
      ngettext(
        "%{count} new reply to «%{title}»",
        "%{count} new replies to «%{title}»",
        count,
        vars(n)
      )

  def text(%Notification{event: "content.item_published", data: %{"kind" => "material"}} = n),
    do: gettext("New material in %{course}: «%{title}»", vars(n))

  def text(%Notification{event: "content.item_published"} = n),
    do: gettext("New page in %{course}: «%{title}»", vars(n))

  def text(%Notification{event: "enrollment.created"} = n),
    do: gettext("You were enrolled in %{course}", vars(n))

  def text(%Notification{} = n), do: n.event

  @doc "Por qué le llega a la persona (RF-NOT-002)."
  def reason(%Notification{reason: "role:student"} = n),
    do: gettext("Because you are a student in %{course}.", vars(n))

  def reason(%Notification{reason: "role:" <> role} = n)
      when role in ~w(course_lead teacher assistant),
      do: gettext("Because you are part of the teaching team of %{course}.", vars(n))

  def reason(%Notification{reason: "role:" <> _} = n),
    do: gettext("Because you take part in %{course}.", vars(n))

  def reason(%Notification{reason: "mentioned"}), do: gettext("Because someone mentioned you.")
  def reason(%Notification{reason: "post_author"}), do: gettext("Because it is your post.")

  def reason(%Notification{reason: "thread_participant"}),
    do: gettext("Because you took part in this conversation.")

  def reason(%Notification{reason: "enrolled"}), do: gettext("Because you were enrolled.")
  def reason(_notification), do: ""

  defp vars(%Notification{} = n) do
    [
      actor: actor(n.actor),
      course: (n.course && n.course.name) || "",
      title: n.data["title"] || ""
    ]
  end

  defp actor(%User{} = user), do: User.display_name(user)
  defp actor(_), do: gettext("Someone")
end
