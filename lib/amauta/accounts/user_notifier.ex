defmodule Amauta.Accounts.UserNotifier do
  @moduledoc """
  Emails de la cuenta (base: phx.gen.auth). Se escriben en el idioma de
  quien los recibe (RF-I18N-006), con el dominio de Gettext `emails`.
  """
  use Gettext, backend: AmautaWeb.Gettext
  import Swoosh.Email

  alias Amauta.Accounts.User

  # Todos los emails de la cuenta son de acceso o seguridad: salen por la
  # cola con la prioridad más alta (RF-EML-001).
  defp deliver(recipient, subject, body) do
    new()
    |> to(recipient)
    |> from(Application.fetch_env!(:amauta, :mail_from))
    |> subject(subject)
    |> text_body(body)
    |> Amauta.Mail.deliver_later(:access)
  end

  @doc "Instrucciones para confirmar un cambio de email."
  def deliver_update_email_instructions(user, url, locale) do
    Gettext.with_locale(AmautaWeb.Gettext, locale, fn ->
      deliver(
        user.email,
        dgettext("emails", "Update email instructions"),
        dgettext(
          "emails",
          """
          Hi %{name},

          You can change your email by visiting the URL below:

          %{url}

          If you didn't request this change, please ignore this.
          """,
          name: user.first_name,
          url: url
        )
      )
    end)
  end

  @doc "Invitación a una institución."
  def deliver_invitation(user, institution, url, locale) do
    Gettext.with_locale(AmautaWeb.Gettext, locale, fn ->
      deliver(
        user.email,
        dgettext("emails", "You are invited to %{institution}", institution: institution.name),
        dgettext(
          "emails",
          """
          Hi %{name},

          %{institution} invited you to Amauta, its learning platform.
          To enter, use the link below:

          %{url}

          The link is valid for 7 days. If it expires, ask for a new one from
          the login page using this email.
          """,
          name: User.given_name(user),
          institution: institution.name,
          url: url
        )
      )
    end)
  end

  @doc "Aviso de inicio de sesión desde un dispositivo nuevo."
  def deliver_new_device_notice(user, user_agent, locale) do
    Gettext.with_locale(AmautaWeb.Gettext, locale, fn ->
      deliver(
        user.email,
        dgettext("emails", "New sign-in to your account"),
        dgettext(
          "emails",
          """
          Hi %{name},

          Someone just signed in to your account from a new device:

          %{device}

          If it was you, you can ignore this message. If it wasn't, change your
          password right away.
          """,
          name: user.first_name,
          device: user_agent || "?"
        )
      )
    end)
  end

  @doc "Aviso de cuenta bloqueada por intentos fallidos."
  def deliver_account_locked_notice(user, locale) do
    Gettext.with_locale(AmautaWeb.Gettext, locale, fn ->
      deliver(
        user.email,
        dgettext("emails", "Too many failed sign-in attempts"),
        dgettext(
          "emails",
          """
          Hi %{name},

          We blocked sign-ins to your account for a few minutes because there
          were too many failed attempts.

          If it wasn't you, someone may be trying to guess your password.
          You can always sign in with a link sent to this email.
          """,
          name: user.first_name
        )
      )
    end)
  end

  @doc """
  Enlace mágico: confirma la cuenta si todavía no lo estaba, o inicia sesión.
  """
  def deliver_login_instructions(%User{confirmed_at: nil} = user, url, locale) do
    Gettext.with_locale(AmautaWeb.Gettext, locale, fn ->
      deliver(
        user.email,
        dgettext("emails", "Confirmation instructions"),
        dgettext(
          "emails",
          """
          Hi %{name},

          You can confirm your account by visiting the URL below:

          %{url}

          If you were not expecting this email, please ignore it.
          """,
          name: user.first_name,
          url: url
        )
      )
    end)
  end

  def deliver_login_instructions(user, url, locale) do
    Gettext.with_locale(AmautaWeb.Gettext, locale, fn ->
      deliver(
        user.email,
        dgettext("emails", "Log in instructions"),
        dgettext(
          "emails",
          """
          Hi %{name},

          You can log into your account by visiting the URL below:

          %{url}

          If you didn't request this email, please ignore this.
          """,
          name: user.first_name,
          url: url
        )
      )
    end)
  end
end
