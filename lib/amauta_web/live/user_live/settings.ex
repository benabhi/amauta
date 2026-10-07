defmodule AmautaWeb.UserLive.Settings do
  @moduledoc "Ajustes de la cuenta: foto de perfil (RF-USR-001), email y contraseña. Exige modo sudo."
  use AmautaWeb, :live_view

  on_mount {AmautaWeb.UserAuth, :require_sudo_mode}

  alias Amauta.{Accounts, Actions}
  alias Amauta.Accounts.User
  alias Amauta.Files.Actions.RemoveAvatar
  alias AmautaWeb.Components.DirectUpload
  alias AmautaWeb.Paths

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("Account Settings")}
        <:subtitle>{gettext("Manage your account email address and password settings")}</:subtitle>
      </.header>

      <div class="flex flex-col gap-6">
        <.card>
          <:header>{gettext("Profile photo")}</:header>
          <div class="flex flex-wrap items-center gap-4">
            <div id="current-avatar">
              <.avatar
                name={User.display_name(@current_scope.user)}
                src={Paths.avatar(@current_scope, @current_scope.user)}
                size="lg"
              />
            </div>
            <div class="min-w-60 flex-1">
              <.live_component
                module={DirectUpload}
                id="avatar-upload"
                current_scope={@current_scope}
                purpose="avatar"
                accept="image/png,image/jpeg,image/gif,image/webp"
                label={gettext("Upload a photo")}
                hint={gettext("PNG, JPG, GIF or WebP, up to 5 MB.")}
              />
            </div>
          </div>
          <.button
            :if={@current_scope.user.avatar_file_id}
            variant="ghost"
            size="sm"
            icon="trash"
            phx-click="remove_avatar"
            class="mt-3"
          >
            {gettext("Remove photo")}
          </.button>
        </.card>

        <.card>
          <:header>{gettext("Email")}</:header>
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.button phx-disable-with={gettext("Changing...")}>{gettext("Change Email")}</.button>
          </.form>
        </.card>

        <.card>
          <:header>{gettext("Password")}</:header>
          <.form
            for={@password_form}
            id="password_form"
            action={Paths.update_password(@current_scope)}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              spellcheck="false"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label={gettext("New password")}
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label={gettext("Confirm new password")}
              autocomplete="new-password"
              spellcheck="false"
            />
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save Password")}</.button>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      case Accounts.update_user_email(scope, scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: Paths.settings(scope))}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    {:ok,
     socket
     |> assign(:current_email, user.email)
     |> assign(:email_form, to_form(email_changeset))
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    scope = socket.assigns.current_scope
    user = scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          scope,
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &Paths.absolute(Paths.confirm_email(scope, &1))
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, put_flash(socket, :info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("remove_avatar", _params, socket) do
    scope = socket.assigns.current_scope

    case Actions.run(RemoveAvatar, scope, %{"user_id" => scope.user.id}) do
      {:ok, user} -> {:noreply, refresh_user(socket, user)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  @impl true
  def handle_info({DirectUpload, "avatar-upload", {:uploaded, _file}}, socket) do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> refresh_user(Accounts.get_user!(scope, scope.user.id))
     |> put_flash(:info, gettext("Profile photo updated."))}
  end

  # Cualquier otro mensaje (por ejemplo, el aviso de un email enviado) se
  # ignora: sin esta cláusula, la vista se caería.
  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh_user(socket, user) do
    %{current_scope: scope} = socket.assigns

    assign(socket,
      current_scope: %{scope | user: %{scope.user | avatar_file_id: user.avatar_file_id}}
    )
  end
end
