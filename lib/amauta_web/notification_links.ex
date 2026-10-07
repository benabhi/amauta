defmodule AmautaWeb.NotificationLinks do
  @moduledoc """
  URLs absolutas que necesitan los emails de notificación
  (`Amauta.Notifications.Email`): el dominio no conoce la capa web, la
  recibe por `config :amauta, :notification_links`.

  La baja lleva un token firmado (sin sesión: se usa desde el cliente de
  correo, RFC 8058) que identifica a la persona en su institución.
  """
  alias AmautaWeb.Paths

  @salt "notifications unsubscribe"
  # Un enlace de baja sirve durante un año.
  @max_age 365 * 24 * 60 * 60

  def target(institution, notification),
    do: Paths.absolute(Paths.notification_target(institution, notification))

  def preferences(institution), do: Paths.absolute(Paths.notification_settings(institution))

  def unsubscribe(institution, user),
    do: Paths.absolute(Paths.unsubscribe(institution, unsubscribe_token(institution, user)))

  @doc "Token de baja de una persona en su institución."
  def unsubscribe_token(institution, user),
    do: Phoenix.Token.sign(AmautaWeb.Endpoint, @salt, {institution.id, user.id})

  @doc "Verifica un token de baja: `{:ok, {institution_id, user_id}}` o error."
  def verify_unsubscribe(token),
    do: Phoenix.Token.verify(AmautaWeb.Endpoint, @salt, token, max_age: @max_age)
end
