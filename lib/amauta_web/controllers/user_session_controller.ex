defmodule AmautaWeb.UserSessionController do
  @moduledoc """
  Inicio y cierre de sesión, y cambio de contraseña (base: phx.gen.auth).

  La autenticación pasa por los proveedores de identidad
  (`Amauta.Accounts.authenticate/3`, RF-AUT-008) y la contraseña, además,
  por el límite de intentos (`LoginThrottle`, RF-AUT-006). Al entrar desde
  un dispositivo nuevo se le avisa a la persona por email.
  """
  use AmautaWeb, :controller

  alias Amauta.Accounts
  alias Amauta.Accounts.{LoginThrottle, SecurityEmailWorker}
  alias AmautaWeb.{Paths, UserAuth}

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, gettext("User confirmed successfully."))
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back!"))
  end

  # Enlace mágico.
  defp create(conn, %{"user" => %{"token" => _} = user_params}, info) do
    institution = conn.assigns.current_institution

    case Accounts.authenticate(institution, :magic_link, user_params) do
      {:ok, user, %{disconnect: tokens}} ->
        UserAuth.disconnect_sessions(tokens)
        log_in(conn, user, user_params, info)

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, gettext("The link is invalid or it has expired."))
        |> redirect(to: Paths.log_in(institution))
    end
  end

  # Email y contraseña.
  defp create(conn, %{"user" => %{"email" => email} = user_params}, info) do
    institution = conn.assigns.current_institution

    with :ok <- LoginThrottle.check(institution.id, conn.remote_ip, email),
         {:ok, user, _meta} <- Accounts.authenticate(institution, :password, user_params) do
      LoginThrottle.record_success(institution.id, email)
      log_in(conn, user, user_params, info)
    else
      {:error, {:locked, seconds}} ->
        conn
        |> put_flash(:error, locked_message(seconds))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: Paths.log_in(institution))

      {:error, :invalid_credentials} ->
        if LoginThrottle.record_failure(institution.id, conn.remote_ip, email) == :locked do
          notify_locked_account(institution, email)
        end

        # La misma respuesta exista o no la cuenta (RNF-SEG-019).
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: Paths.log_in(institution))
    end
  end

  defp log_in(conn, user, user_params, info) do
    institution = conn.assigns.current_institution

    conn =
      case UserAuth.safe_return_to(institution, user_params["return_to"]) do
        nil -> conn
        path -> put_session(conn, :user_return_to, path)
      end

    user_agent = conn |> get_req_header("user-agent") |> List.first()

    if Accounts.register_device(institution, user, user_agent) == :new do
      SecurityEmailWorker.new_for(institution, %{
        "user_id" => user.id,
        "kind" => "new_device",
        "user_agent" => user_agent
      })
      |> Oban.insert!()
    end

    conn
    |> put_flash(:info, info)
    |> UserAuth.log_in_user(user, user_params)
  end

  defp notify_locked_account(institution, email) do
    if user = Accounts.get_user_by_email(institution, email) do
      SecurityEmailWorker.new_for(institution, %{"user_id" => user.id, "kind" => "account_locked"})
      |> Oban.insert!()
    end
  end

  defp locked_message(seconds) do
    minutes = max(div(seconds + 59, 60), 1)

    ngettext(
      "Too many failed attempts. Try again in %{count} minute or use a link sent to your email.",
      "Too many failed attempts. Try again in %{count} minutes or use a link sent to your email.",
      minutes
    )
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
