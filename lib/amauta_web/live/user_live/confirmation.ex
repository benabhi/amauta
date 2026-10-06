defmodule AmautaWeb.UserLive.Confirmation do
  @moduledoc "Destino del enlace mágico: confirma la cuenta e inicia sesión (RF-AUT-002 y 003)."
  use AmautaWeb, :live_view

  alias Amauta.Accounts
  alias AmautaWeb.Paths

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="sm">
      <div class="pt-6">
        <.header>
          {gettext("Welcome %{name}", name: @user.first_name)}
          <:subtitle>{@current_scope.institution.name}</:subtitle>
        </.header>

        <.card>
          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={Paths.log_in(@current_scope) <> "?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
            class="flex flex-col gap-2"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={gettext("Confirming...")}
              class="w-full"
            >
              {gettext("Confirm and stay logged in")}
            </.button>
            <.button phx-disable-with={gettext("Confirming...")} variant="secondary" class="w-full">
              {gettext("Confirm and log in only this time")}
            </.button>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={Paths.log_in(@current_scope)}
            phx-trigger-action={@trigger_submit}
            class="flex flex-col gap-2"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <%= if @current_scope.user do %>
              <.button phx-disable-with={gettext("Logging in...")} class="w-full">
                {gettext("Log in")}
              </.button>
            <% else %>
              <.button
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with={gettext("Logging in...")}
                class="w-full"
              >
                {gettext("Keep me logged in on this device")}
              </.button>
              <.button phx-disable-with={gettext("Logging in...")} variant="secondary" class="w-full">
                {gettext("Log me in only this time")}
              </.button>
            <% end %>
          </.form>

          <p :if={!@user.confirmed_at} class="mt-5 flex gap-2 text-sm text-ink-muted">
            <.icon name="info" class="mt-0.5 size-4 shrink-0" />
            {gettext("Tip: If you prefer passwords, you can enable them in the user settings.")}
          </p>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    scope = socket.assigns.current_scope

    if user = Accounts.get_user_by_magic_link_token(scope, token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Magic link is invalid or it has expired."))
       |> push_navigate(to: Paths.log_in(scope))}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
