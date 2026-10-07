defmodule AmautaWeb.UserAuth do
  @moduledoc """
  Autenticación web por institución (base: phx.gen.auth).

  Cada institución tiene su propia clave de sesión y su propia cookie
  «recordarme», así una sesión en una institución nunca vale en otra.
  Requiere que `AmautaWeb.Plugs.Tenant` haya resuelto la institución.
  """
  use AmautaWeb, :verified_routes
  use Gettext, backend: AmautaWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller

  alias Amauta.{Accounts, Scope}
  alias Amauta.Platform.Institution
  alias AmautaWeb.Paths

  # La cookie «recordarme» vale 14 días, igual que el token de sesión.
  @max_cookie_age_in_days 14
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # Antigüedad a partir de la cual se renueva el token de sesión.
  @session_reissue_age_in_days 7

  @doc "Clave de sesión del token de la institución."
  def session_token_key(%Institution{id: id}), do: "user_token:#{id}"

  defp remember_me_cookie(%Institution{id: id}), do: "_amauta_remember_me_#{id}"

  @doc """
  Inicia la sesión y redirige a `:user_return_to` o al inicio de la
  institución.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> delete_session(:user_return_to)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  La ruta a la que volver después de entrar, si es segura: una ruta
  interna de la misma institución. Cualquier otra cosa (otro sitio, otra
  institución, `//host`) da `nil`, para no abrir una redirección.
  """
  @spec safe_return_to(Institution.t(), term()) :: String.t() | nil
  def safe_return_to(%Institution{slug: slug}, "/" <> _ = path) do
    prefix = "/#{slug}/"

    if String.starts_with?(path, prefix) and not String.contains?(path, ["//", "\\", "\n", "\r"]),
      do: path
  end

  def safe_return_to(_institution, _path), do: nil

  @doc "Cierra la sesión de la institución actual."
  def log_out_user(conn) do
    institution = conn.assigns.current_institution
    user_token = get_session(conn, session_token_key(institution))
    user_token && Accounts.delete_user_session_token(institution, user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AmautaWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(remember_me_cookie(institution), @remember_me_options)
    |> redirect(to: Paths.log_in(institution))
  end

  @doc """
  Arma `:current_scope` con la persona de la sesión o de la cookie
  «recordarme». Renueva el token si ya es viejo.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    institution = conn.assigns.current_institution

    with {token, conn} <- ensure_user_token(conn, institution),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(institution, token) do
      conn
      |> assign(:current_scope, Scope.for_user(institution, user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_institution(institution))
    end
  end

  defp ensure_user_token(conn, institution) do
    if token = get_session(conn, session_token_key(institution)) do
      {token, conn}
    else
      cookie = remember_me_cookie(institution)
      conn = fetch_cookies(conn, signed: [cookie])

      if token = conn.cookies[cookie] do
        {token,
         conn
         |> put_token_in_session(institution, token)
         |> put_session(:user_remember_me, true)}
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # Crea o extiende la sesión. Al crearla, renueva el ID de sesión y la
  # limpia para evitar ataques de fijación de sesión.
  defp create_or_extend_session(conn, user, params) do
    institution = conn.assigns.current_institution
    token = Accounts.generate_user_session_token(institution, user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(institution, token)
    |> maybe_write_remember_me_cookie(institution, token, params, remember_me)
  end

  # Si la persona ya tenía la sesión iniciada, no se renueva: evita errores
  # de CSRF en otras pestañas abiertas.
  defp renew_session(%{assigns: %{current_scope: %Scope{user: %{id: id}}}} = conn, %{id: id}),
    do: conn

  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, institution, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, institution, token)

  defp maybe_write_remember_me_cookie(conn, institution, token, _params, true),
    do: write_remember_me_cookie(conn, institution, token)

  defp maybe_write_remember_me_cookie(conn, _institution, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, institution, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(remember_me_cookie(institution), token, @remember_me_options)
  end

  defp put_token_in_session(conn, institution, token) do
    conn
    |> put_session(session_token_key(institution), token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc "Desconecta las LiveViews de los tokens dados."
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      AmautaWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Monta `:current_scope` en las LiveViews de una institución.

    * `:mount_current_scope` - con o sin persona.
    * `:require_authenticated` - exige persona; si no, va al inicio de sesión.
    * `:require_sudo_mode` - exige haberse autenticado hace poco.
  """
  def on_mount(:mount_current_scope, params, session, socket) do
    {:cont, mount_current_scope(socket, params, session)}
  end

  def on_mount(:require_authenticated, params, session, socket) do
    socket = mount_current_scope(socket, params, session)

    if socket.assigns.current_scope.user do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, gettext("You must log in to access this page."))
       |> Phoenix.LiveView.redirect(to: Paths.log_in(socket.assigns.current_scope))}
    end
  end

  def on_mount(:require_sudo_mode, params, session, socket) do
    socket = mount_current_scope(socket, params, session)
    scope = socket.assigns.current_scope

    if Accounts.sudo_mode?(scope.user, -10) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(
         :error,
         gettext("You must re-authenticate to access this page.")
       )
       |> Phoenix.LiveView.redirect(to: Paths.log_in_return(scope, Paths.settings(scope)))}
    end
  end

  defp mount_current_scope(socket, %{"institution" => slug}, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      institution = AmautaWeb.Plugs.Tenant.resolve!(slug)

      {user, _} =
        if user_token = session[session_token_key(institution)] do
          Accounts.get_user_by_session_token(institution, user_token)
        end || {nil, nil}

      Scope.for_user(institution, user)
    end)
  end

  @doc "Ruta a la que se va después de iniciar sesión."
  def signed_in_path(%Plug.Conn{assigns: %{current_institution: institution}}),
    do: Paths.home(institution)

  @doc "Plug para rutas que exigen persona autenticada."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, gettext("You must log in to access this page."))
      |> maybe_store_return_to()
      |> redirect(to: Paths.log_in(conn.assigns.current_institution))
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
