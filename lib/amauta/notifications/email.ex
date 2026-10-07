defmodule Amauta.Notifications.Email do
  @moduledoc """
  El email de notificaciones (RF-EML-004, 007 y 009): una plantilla fija,
  localizada y con el nombre de la institución, en HTML y en texto plano.
  Lleva el «por qué» de cada aviso, el enlace a las preferencias y la baja
  con un clic (cabeceras `List-Unsubscribe` y `List-Unsubscribe-Post`,
  RFC 8058).

  Las URLs las arma la capa web (`config :amauta, :notification_links`).
  """
  use Gettext, backend: AmautaWeb.Gettext
  import Swoosh.Email

  alias Amauta.Accounts.User
  alias Amauta.Notifications.Message

  def digest(%User{} = user, institution, notifications) do
    links = Application.fetch_env!(:amauta, :notification_links)
    unsubscribe = links.unsubscribe(institution, user)
    preferences = links.preferences(institution)

    items =
      for n <- notifications do
        %{text: Message.text(n), reason: Message.reason(n), url: links.target(institution, n)}
      end

    subject =
      case items do
        [one] ->
          one.text

        _ ->
          ngettext(
            "%{count} new notification in %{institution}",
            "%{count} new notifications in %{institution}",
            length(items),
            institution: institution.name
          )
      end

    new()
    |> to({User.display_name(user), user.email})
    |> from(Application.fetch_env!(:amauta, :mail_from))
    |> subject(subject)
    |> header("List-Unsubscribe", "<#{unsubscribe}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> text_body(text(user, institution, items, preferences, unsubscribe))
    |> html_body(html(user, institution, items, preferences, unsubscribe))
  end

  defp text(user, institution, items, preferences, unsubscribe) do
    lines =
      Enum.map_join(items, "\n\n", fn item ->
        "• #{item.text}\n  #{item.url}\n  #{item.reason}"
      end)

    """
    #{gettext("Hi %{name},", name: User.given_name(user))}

    #{gettext("This is new in %{institution}:", institution: institution.name)}

    #{lines}

    —
    #{gettext("Choose what reaches you by email: %{url}", url: preferences)}
    #{gettext("Stop these emails: %{url}", url: unsubscribe)}
    """
  end

  defp html(user, institution, items, preferences, unsubscribe) do
    rows =
      Enum.map_join(items, "", fn item ->
        """
        <tr><td style="padding:12px 0;border-top:1px solid #E7E2DA">
          <a href="#{escape(item.url)}" style="color:#1F1D1A;font-weight:600;text-decoration:none">#{escape(item.text)}</a>
          <div style="color:#5E5A55;font-size:13px;margin-top:4px">#{escape(item.reason)}</div>
        </td></tr>
        """
      end)

    """
    <!doctype html>
    <html><body style="margin:0;background:#FBF9F6;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;color:#1F1D1A">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#FFFFFF;border:1px solid #E7E2DA;border-radius:12px">
      <tr><td style="padding:20px 24px;border-bottom:1px solid #E7E2DA;font-weight:700;font-size:16px">#{escape(institution.name)}</td></tr>
      <tr><td style="padding:20px 24px">
        <p style="margin:0 0 12px">#{escape(gettext("Hi %{name},", name: User.given_name(user)))}</p>
        <p style="margin:0 0 8px">#{escape(gettext("This is new in %{institution}:", institution: institution.name))}</p>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">#{rows}</table>
      </td></tr>
      <tr><td style="padding:16px 24px;border-top:1px solid #E7E2DA;color:#5E5A55;font-size:12px">
        <a href="#{escape(preferences)}" style="color:#3F57C6">#{escape(gettext("Choose what reaches you by email"))}</a>
        · <a href="#{escape(unsubscribe)}" style="color:#5E5A55">#{escape(gettext("Stop these emails"))}</a>
      </td></tr>
    </table>
    </td></tr></table>
    </body></html>
    """
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
