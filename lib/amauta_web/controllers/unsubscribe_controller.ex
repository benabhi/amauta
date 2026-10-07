defmodule AmautaWeb.UnsubscribeController do
  @moduledoc """
  Baja de los emails de notificación (RF-EML-009). El enlace del email
  muestra una confirmación; el cliente de correo puede dar la baja directo
  con un POST (RFC 8058, `List-Unsubscribe-Post`). El token firmado de la
  URL identifica a la persona (`AmautaWeb.NotificationLinks`): no hace
  falta iniciar sesión.

  Dar la baja apaga el email de todos los eventos; lo que llega en Amauta
  sigue igual, y se puede volver a activar desde las preferencias.
  """
  use AmautaWeb, :controller

  alias Amauta.Accounts.User
  alias Amauta.Notifications
  alias Amauta.Notifications.Catalog
  alias Amauta.{Repo, Scope, Tenancy}
  alias AmautaWeb.{NotificationLinks, Paths}

  def show(conn, %{"token" => token}) do
    case person(conn, token) do
      {:ok, _scope} -> render_page(conn, token, :confirm)
      :error -> render_page(conn, token, :invalid)
    end
  end

  def create(conn, %{"token" => token}) do
    case person(conn, token) do
      {:ok, scope} ->
        for event <- Catalog.events(),
            do: Notifications.set_preference(scope, event, "email", false)

        render_page(conn, token, :done)

      :error ->
        conn |> put_status(:not_found) |> render_page(token, :invalid)
    end
  end

  defp person(conn, token) do
    institution = conn.assigns.current_institution

    with {:ok, {institution_id, user_id}} when institution_id == institution.id <-
           NotificationLinks.verify_unsubscribe(token),
         %User{} = user <- Repo.get(User, user_id, Tenancy.opts(institution)) do
      {:ok, Scope.for_user(institution, user)}
    else
      _ -> :error
    end
  end

  defp render_page(conn, token, state) do
    institution = conn.assigns.current_institution

    conn
    |> put_view(AmautaWeb.UnsubscribeHTML)
    |> render(:show,
      state: state,
      institution: institution,
      preferences: Paths.notification_settings(institution),
      action: Paths.unsubscribe(institution, token)
    )
  end
end

defmodule AmautaWeb.UnsubscribeHTML do
  @moduledoc false
  use AmautaWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width="sm" palette={false}>
      <.card id="unsubscribe">
        <:header>{@institution.name}</:header>
        <div :if={@state == :confirm} class="grid gap-4">
          <p>
            {gettext("Stop receiving notification emails? You will keep seeing them in Amauta.")}
          </p>
          <form method="post" action={@action}>
            <.button icon="check">{gettext("Stop these emails")}</.button>
          </form>
        </div>
        <div :if={@state == :done} class="grid gap-2">
          <p class="font-semibold">{gettext("Done: you will not receive notification emails.")}</p>
          <p class="text-sm text-ink-muted">
            {gettext("You can turn them back on whenever you want from your preferences.")}
          </p>
        </div>
        <p :if={@state == :invalid}>{gettext("This link is not valid or has expired.")}</p>
        <.link
          navigate={@preferences}
          class="mt-4 inline-block text-sm font-semibold text-anil-deep underline"
        >
          {gettext("Notification preferences")}
        </.link>
      </.card>
    </Layouts.app>
    """
  end
end
