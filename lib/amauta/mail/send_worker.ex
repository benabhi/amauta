defmodule Amauta.Mail.SendWorker do
  @moduledoc """
  Envía un email encolado (RF-EML-001 a 003):

    * a una dirección suprimida no se le envía;
    * si se llegó al límite de tasa de la instancia, espera (`snooze`) sin
      gastar un intento;
    * un fallo temporal se reintenta con la espera exponencial de Oban;
    * un fallo permanente (5xx) se registra y cuenta para la supresión.

  Los emails no llevan institución: la cola y el límite son de la instancia.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 8

  require Logger

  alias Amauta.Mail
  alias Amauta.Mail.RateLimit

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case RateLimit.acquire() do
      :ok -> send_now(args)
      {:wait, seconds} -> {:snooze, seconds}
    end
  end

  @doc "Envía ya (sin mirar el límite de tasa). Lo usa también el modo en línea."
  def send_now(args) do
    email = Mail.deserialize(args)
    [{_name, address} | _] = email.to

    if Mail.suppressed?(address) do
      Logger.info("email not sent: #{address} is suppressed")
      {:cancel, :suppressed}
    else
      case Amauta.Mailer.deliver(email) do
        {:ok, _metadata} ->
          :ok

        {:error, reason} ->
          if permanent?(reason) do
            Logger.warning("permanent email failure for #{address}: #{inspect(reason)}")
            Mail.record_bounce(address, inspect(reason))
            {:cancel, :permanent_failure}
          else
            {:error, reason}
          end
      end
    end
  end

  # gen_smtp informa los rechazos definitivos (5xx) como permanent_failure.
  defp permanent?(reason), do: inspect(reason) =~ "permanent_failure"
end
