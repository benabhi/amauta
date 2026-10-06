defmodule Amauta.Accounts.UserNotifier do
  @moduledoc """
  Emails de la cuenta (base: phx.gen.auth). Se escriben en el idioma de
  quien los recibe (RF-I18N-006), con el dominio de Gettext `emails`.
  """
  use Gettext, backend: AmautaWeb.Gettext
  import Swoosh.Email

  alias Amauta.Accounts.User
  alias Amauta.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:amauta, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
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
