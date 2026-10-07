defmodule AmautaWeb.SetupLive do
  @moduledoc """
  Asistente de primera ejecución (RF-ADM-001): crea la cuenta de
  superadministración. Solo existe mientras no haya ninguna; después,
  `/setup` lleva a la administración, donde se crea la primera institución.

  El almacenamiento, el SMTP y la URL base se configuran por variables de
  entorno en el MVP.
  """
  use AmautaWeb, :live_view

  alias Amauta.Platform.StaffAccounts

  @impl true
  def mount(_params, _session, socket) do
    if StaffAccounts.setup_required?() do
      {:ok,
       assign(socket, form: to_form(StaffAccounts.change_registration()), trigger_submit: false)}
    else
      {:ok, push_navigate(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("validate", %{"staff" => params}, socket) do
    changeset = params |> StaffAccounts.change_registration() |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"staff" => params}, socket) do
    case StaffAccounts.create_first_superadmin(params) do
      {:ok, _staff} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Your account is ready. Log in to create the first institution.")
         )
         |> push_navigate(to: ~p"/admin/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :already_set_up} ->
        {:noreply, push_navigate(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width="sm">
      <div class="pt-6">
        <.header>
          {gettext("Welcome to Amauta")}
          <:subtitle>
            {gettext(
              "Create the administration account for this instance. You will use it to create institutions and assign their administrators."
            )}
          </:subtitle>
        </.header>

        <.card>
          <.form for={@form} id="setup_form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} label={gettext("Your name")} autocomplete="name" required />
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
              hint={gettext("At least 12 characters.")}
              autocomplete="new-password"
              required
            />
            <.button class="w-full" phx-disable-with={gettext("Creating...")}>
              {gettext("Create account")}
            </.button>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
