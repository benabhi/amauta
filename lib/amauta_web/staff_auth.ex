defmodule AmautaWeb.StaffAuth do
  @moduledoc """
  Sesión del personal de plataforma (`/admin`), separada de las sesiones de
  las instituciones: usa su propia clave de sesión y no tiene «recordarme».
  """
  use AmautaWeb, :verified_routes
  use Gettext, backend: AmautaWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller

  alias Amauta.Platform.StaffAccounts

  @session_key "staff_token"

  def log_in_staff(conn, staff) do
    token = StaffAccounts.generate_session_token(staff)

    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, token)
    |> redirect(to: ~p"/admin")
  end

  def log_out_staff(conn) do
    if token = get_session(conn, @session_key), do: StaffAccounts.delete_session_token(token)

    conn
    |> delete_session(@session_key)
    |> configure_session(renew: true)
    |> redirect(to: ~p"/admin/log-in")
  end

  @doc "Plug: asigna `:current_staff` (o `nil`)."
  def fetch_current_staff(conn, _opts) do
    staff =
      case get_session(conn, @session_key) do
        nil -> nil
        token -> StaffAccounts.get_staff_by_session_token(token)
      end

    assign(conn, :current_staff, staff)
  end

  @doc "Plug: exige personal autenticado."
  def require_staff(conn, _opts) do
    if conn.assigns[:current_staff] do
      conn
    else
      conn
      |> put_flash(:error, gettext("You must log in to access this page."))
      |> redirect(to: ~p"/admin/log-in")
      |> halt()
    end
  end

  @doc "Plug: si la instancia todavía no tiene superadministración, va al asistente."
  def redirect_to_setup(conn, _opts) do
    if StaffAccounts.setup_required?() do
      conn |> redirect(to: ~p"/setup") |> halt()
    else
      conn
    end
  end

  def on_mount(:require_staff, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_staff, fn ->
        session[@session_key] && StaffAccounts.get_staff_by_session_token(session[@session_key])
      end)

    if socket.assigns.current_staff do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/admin/log-in")}
    end
  end
end
