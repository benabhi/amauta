defmodule AmautaWeb.UserLive.Login do
  @moduledoc "Inicio de sesión de una institución: enlace mágico o contraseña (RF-AUT-001 y 002)."
  use AmautaWeb, :live_view

  alias Amauta.Accounts
  alias AmautaWeb.Paths

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>{@current_scope.institution.name}</p>
            <:subtitle>
              <%= if @current_scope.user do %>
                {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
              <% else %>
                {gettext("Log in to continue.")}
              <% end %>
            </:subtitle>
          </.header>
        </div>

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
          <.button class="btn btn-primary w-full">
            {gettext("Log in with email")} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">{gettext("or")}</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={Paths.log_in(@current_scope)}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
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
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            {gettext("Log in only this time")}
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    scope = socket.assigns.current_scope

    if user = Accounts.get_user_by_email(scope, email) do
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
