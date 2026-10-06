defmodule AmautaWeb.UserSessionController do
  @moduledoc "Inicio y cierre de sesión, y cambio de contraseña (base: phx.gen.auth)."
  use AmautaWeb, :controller

  alias Amauta.Accounts
  alias AmautaWeb.{Paths, UserAuth}

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, gettext("User confirmed successfully."))
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back!"))
  end

  # Enlace mágico.
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    institution = conn.assigns.current_institution

    case Accounts.login_user_by_magic_link(institution, token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, gettext("The link is invalid or it has expired."))
        |> redirect(to: Paths.log_in(institution))
    end
  end

  # Email y contraseña.
  defp create(conn, %{"user" => user_params}, info) do
    institution = conn.assigns.current_institution
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(institution, email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # No se revela si el email está registrado.
      conn
      |> put_flash(:error, gettext("Invalid email or password"))
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: Paths.log_in(institution))
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    scope = conn.assigns.current_scope
    true = Accounts.sudo_mode?(scope.user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(scope, scope.user, user_params)

    # Desconecta las LiveViews de las sesiones anteriores.
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, Paths.settings(scope))
    |> create(params, gettext("Password updated successfully!"))
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
