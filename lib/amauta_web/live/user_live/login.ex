defmodule AmautaWeb.UserLive.Login do
  @moduledoc "Inicio de sesión de una institución: enlace mágico o contraseña (RF-AUT-001 y 002)."
  use AmautaWeb, :live_view

  alias Amauta.Accounts
  alias Amauta.Accounts.LoginThrottle
  alias AmautaWeb.{Paths, UserAuth}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="sm">
      <div class="pt-6">
        <.header>
          {@current_scope.institution.name}
          <:subtitle>
            <%= if @current_scope.user do %>
              {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
            <% else %>
              {gettext("Log in to continue.")}
            <% end %>
          </:subtitle>
        </.header>

        <.card>
          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={Paths.log_in(@current_scope)}
            phx-submit="submit_magic"
          >
            <.input
              readonly={!!@current_scope.user}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="w-full" icon="envelope">{gettext("Log in with email")}</.button>
          </.form>

          <div class="my-5">
            <.divider>{gettext("or")}</.divider>
          </div>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={Paths.log_in(@current_scope)}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <input :if={@return_to} type="hidden" name="user[return_to]" value={@return_to} />
            <.input
              readonly={!!@current_scope.user}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              autocomplete="current-password"
              spellcheck="false"
            />
            <div class="flex flex-col gap-2">
              <.button class="w-full" name={@form[:remember_me].name} value="true">
                {gettext("Log in and stay logged in")}
              </.button>
              <.button class="w-full" variant="secondary">{gettext("Log in only this time")}</.button>
            </div>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    # Adónde volver después de entrar (por ejemplo, Ajustes, que pide volver a
    # autenticarse). Solo rutas internas de la institución.
    return_to =
      UserAuth.safe_return_to(socket.assigns.current_scope.institution, params["return_to"])

    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, return_to: return_to)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    scope = socket.assigns.current_scope

    # Límite de envíos por cuenta, para no usar la plataforma para inundar un
    # buzón (RF-AUT-006). La respuesta es siempre la misma.
    with true <- LoginThrottle.allow_magic_link?(scope.institution.id, email),
         %Accounts.User{} = user <- Accounts.get_user_by_email(scope, email) do
      Accounts.deliver_login_instructions(scope, user, &Paths.absolute(Paths.log_in(scope, &1)))
    end

    # No se revela si el email está registrado.
    info =
      gettext(
        "If your email is in our system, you will receive instructions for logging in shortly."
      )

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: Paths.log_in(scope))}
  end
end
