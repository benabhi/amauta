defmodule AmautaWeb.Locale do
  @moduledoc """
  Fija el idioma de cada solicitud (RF-I18N-004): preferencia de la
  persona, institución, instancia. Como plug va después de resolver la
  persona; como `on_mount`, después de `AmautaWeb.UserAuth`.
  """
  import Plug.Conn

  alias Amauta.{Locale, Scope}

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale = locale_for(conn.assigns[:current_scope])
    Locale.put(locale)
    assign(conn, :locale, locale)
  end

  def on_mount(:default, _params, _session, socket) do
    locale = locale_for(socket.assigns[:current_scope])
    Locale.put(locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp locale_for(%Scope{user: user, institution: institution}),
    do: Locale.resolve(user, institution)

  defp locale_for(_), do: Locale.default()
end
