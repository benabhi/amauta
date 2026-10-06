defmodule AmautaWeb.Admin.SessionController do
  @moduledoc "Inicio y cierre de sesión del personal de plataforma."
  use AmautaWeb, :controller

  alias Amauta.Accounts.LoginThrottle
  alias Amauta.Platform.StaffAccounts
  alias AmautaWeb.StaffAuth

  # El limitador de intentos usa este ámbito para el personal de plataforma.
  @throttle_scope "platform"

  def new(conn, _params) do
    if conn.assigns.current_staff do
      redirect(conn, to: ~p"/admin")
    else
      email = Phoenix.Flash.get(conn.assigns.flash, :email)
      render(conn, :new, form: Phoenix.Component.to_form(%{"email" => email}, as: "staff"))
    end
  end

  def create(conn, %{"staff" => %{"email" => email, "password" => password}}) do
    with :ok <- LoginThrottle.check(@throttle_scope, conn.remote_ip, email),
         %{} = staff <- StaffAccounts.get_staff_by_email_and_password(email, password) do
      LoginThrottle.record_success(@throttle_scope, email)
      StaffAuth.log_in_staff(conn, staff)
    else
      {:error, {:locked, _seconds}} ->
        conn
        |> put_flash(:error, gettext("Too many failed attempts. Try again in a few minutes."))
        |> redirect(to: ~p"/admin/log-in")

      nil ->
        LoginThrottle.record_failure(@throttle_scope, conn.remote_ip, email)

        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/admin/log-in")
    end
  end

  def delete(conn, _params), do: StaffAuth.log_out_staff(conn)
end

defmodule AmautaWeb.Admin.SessionHTML do
  @moduledoc false
  use AmautaWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width="sm">
      <div class="pt-6">
        <.header>
          {gettext("Instance administration")}
          <:subtitle>{gettext("Log in with your administration account.")}</:subtitle>
        </.header>
        <.card>
          <.form for={@form} id="staff_login" action={~p"/admin/log-in"}>
            <.input
              field={@form[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              autocomplete="current-password"
              required
            />
            <.button class="w-full" icon="sign-in">{gettext("Log in")}</.button>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
