defmodule Amauta.Mail do
  @moduledoc """
  Salida del correo (capacidad C13). Ningún email se envía dentro de la
  acción de una persona: todos pasan por una cola persistente
  (`Amauta.Mail.SendWorker`) con prioridades (RF-EML-001):

    * `:access`: enlace mágico, invitaciones, avisos de seguridad;
    * `:notification`: notificaciones agrupadas;
    * `:bulk`: envíos masivos.

  El worker respeta el límite de tasa de la instancia (RF-EML-002), reintenta
  con espera exponencial y lleva la lista de supresión (RF-EML-003).

  Con `config :amauta, Amauta.Mail, inline: true` (los tests) el envío pasa
  por el mismo camino, pero en el momento.
  """
  import Ecto.Query

  alias Amauta.Mail.{SendWorker, Suppression}
  alias Amauta.Repo

  @priorities %{access: 0, notification: 1, bulk: 3}
  @max_bounces 3

  @doc "Cuántos fallos permanentes suprimen una dirección."
  def max_bounces, do: @max_bounces

  @doc """
  Encola un email (`Swoosh.Email`) con la prioridad de su tipo. Devuelve
  `{:ok, email}`.
  """
  def deliver_later(%Swoosh.Email{} = email, kind \\ :notification) do
    args = serialize(email)

    if config(:inline, false) do
      SendWorker.send_now(args)
    else
      args |> SendWorker.new(priority: Map.fetch!(@priorities, kind)) |> Oban.insert!()
    end

    {:ok, email}
  end

  defp config(key, default),
    do: Application.get_env(:amauta, __MODULE__, []) |> Keyword.get(key, default)

  ## Serialización (los argumentos de Oban son JSON)

  @doc false
  def serialize(%Swoosh.Email{} = email) do
    %{
      "to" => Enum.map(email.to, &address/1),
      "from" => address(email.from),
      "reply_to" => email.reply_to && address(email.reply_to),
      "subject" => email.subject,
      "text_body" => email.text_body,
      "html_body" => email.html_body,
      "headers" => email.headers
    }
  end

  @doc false
  def deserialize(args) do
    email =
      Swoosh.Email.new(
        to: Enum.map(args["to"], &tuple/1),
        from: tuple(args["from"]),
        subject: args["subject"],
        text_body: args["text_body"],
        html_body: args["html_body"]
      )

    email =
      if args["reply_to"], do: Swoosh.Email.reply_to(email, tuple(args["reply_to"])), else: email

    Enum.reduce(args["headers"] || %{}, email, fn {name, value}, acc ->
      Swoosh.Email.header(acc, name, value)
    end)
  end

  defp address({name, address}), do: [name, address]
  defp address(address) when is_binary(address), do: ["", address]

  defp tuple([name, address]), do: {name, address}

  ## Supresión (RF-EML-003)

  @doc "Si a la dirección ya no se le envía."
  def suppressed?(address) do
    from(s in Suppression,
      where: s.address == ^address and not is_nil(s.suppressed_at),
      select: true
    )
    |> Repo.exists?()
  end

  @doc "Registra un fallo permanente; al llegar al máximo, suprime la dirección."
  def record_bounce(address, error) do
    now = DateTime.utc_now()

    Repo.insert!(
      %Suppression{address: address, bounces: 1, last_error: error},
      on_conflict:
        from(s in Suppression,
          update: [
            inc: [bounces: 1],
            set: [last_error: ^error, updated_at: ^now]
          ]
        ),
      conflict_target: :address
    )

    from(s in Suppression,
      where: s.address == ^address and s.bounces >= ^@max_bounces and is_nil(s.suppressed_at)
    )
    |> Repo.update_all(set: [suppressed_at: now])

    :ok
  end
end
