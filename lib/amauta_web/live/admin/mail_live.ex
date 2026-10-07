defmodule AmautaWeb.Admin.MailLive do
  @moduledoc """
  Correo de la instancia (RF-EML-006, parcial): cómo está configurado
  (servidor, remitente y límite de tasa, que salen de variables de entorno),
  el estado de la cola, las direcciones suprimidas y una prueba de envío.
  """
  use AmautaWeb, :live_view

  import Ecto.Query

  alias Amauta.Mail
  alias Amauta.Mail.{RateLimit, Suppression}
  alias Amauta.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Email"),
       form: to_form(%{"to" => socket.assigns.current_staff.email})
     )
     |> load()}
  end

  defp load(socket) do
    queue =
      from(j in Oban.Job,
        where:
          j.queue == "mailers" and j.state in ["available", "scheduled", "retryable", "executing"],
        group_by: j.state,
        select: {j.state, count()}
      )
      |> Repo.all(prefix: "global")
      |> Map.new()

    suppressed =
      from(s in Suppression, where: not is_nil(s.suppressed_at), select: count())
      |> Repo.one()

    config = Application.get_env(:amauta, Amauta.Mailer, [])

    assign(socket,
      queue: queue,
      suppressed: suppressed,
      adapter:
        config
        |> Keyword.get(:adapter)
        |> inspect()
        |> String.replace_prefix("Swoosh.Adapters.", ""),
      relay: config[:relay],
      from: Application.fetch_env!(:amauta, :mail_from),
      limits: RateLimit.limits()
    )
  end

  @impl true
  def handle_event("send_test", %{"to" => to}, socket) do
    to = String.trim(to)

    if to =~ ~r/^[^\s@]+@[^\s@]+$/ do
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from(Application.fetch_env!(:amauta, :mail_from))
      |> Swoosh.Email.subject(gettext("Amauta test email"))
      |> Swoosh.Email.text_body(gettext("If you are reading this, Amauta can send emails."))
      |> Mail.deliver_later(:access)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Test email queued for %{to}.", to: to))
       |> load()}
    else
      {:noreply, put_flash(socket, :error, gettext("Write a valid email address."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_staff={@current_staff} active={:mail}>
      <.header>
        {gettext("Email")}
        <:subtitle>
          {gettext("The server, sender and rate limit come from environment variables.")}
        </:subtitle>
      </.header>

      <div class="grid gap-6 md:grid-cols-2">
        <.card id="mail-config">
          <:header>{gettext("Configuration")}</:header>
          <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            <dt class="text-ink-muted">{gettext("Adapter")}</dt>
            <dd>{@adapter}</dd>
            <dt :if={@relay} class="text-ink-muted">{gettext("Server")}</dt>
            <dd :if={@relay}>{@relay}</dd>
            <dt class="text-ink-muted">{gettext("Sender")}</dt>
            <dd>{elem(@from, 0)} &lt;{elem(@from, 1)}&gt;</dd>
            <dt class="text-ink-muted">{gettext("Rate limit")}</dt>
            <dd>
              {@limits
              |> Enum.filter(&elem(&1, 1))
              |> Enum.map_join(" · ", fn {window, n} -> "#{n}/#{window_label(window)}" end)}
            </dd>
          </dl>
        </.card>

        <.card id="mail-queue">
          <:header>{gettext("Queue")}</:header>
          <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            <dt class="text-ink-muted">{gettext("Waiting")}</dt>
            <dd>{Map.get(@queue, "available", 0) + Map.get(@queue, "scheduled", 0)}</dd>
            <dt class="text-ink-muted">{gettext("Retrying")}</dt>
            <dd>{Map.get(@queue, "retryable", 0)}</dd>
            <dt class="text-ink-muted">{gettext("Suppressed addresses")}</dt>
            <dd>{@suppressed}</dd>
          </dl>
        </.card>
      </div>

      <.card id="mail-test" class="mt-6">
        <:header>{gettext("Send a test email")}</:header>
        <.form
          for={@form}
          id="mail-test-form"
          phx-submit="send_test"
          class="flex flex-wrap items-end gap-3"
        >
          <div class="min-w-64 flex-1">
            <.input field={@form[:to]} type="email" label={gettext("To")} required />
          </div>
          <div class="mb-4">
            <.button icon="paper-plane-tilt">{gettext("Send")}</.button>
          </div>
        </.form>
      </.card>
    </Layouts.admin>
    """
  end

  defp window_label(:second), do: gettext("second")
  defp window_label(:minute), do: gettext("minute")
  defp window_label(:hour), do: gettext("hour")
  defp window_label(:day), do: gettext("day")
end
