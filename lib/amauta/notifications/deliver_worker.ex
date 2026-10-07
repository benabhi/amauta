defmodule Amauta.Notifications.DeliverWorker do
  @moduledoc """
  Entrega un evento en segundo plano (RF-NOT-008): arma la audiencia
  (`Amauta.Notifications.Audience`) y crea las notificaciones por lotes,
  sin demorar la acción que lo originó. Las acciones lo encolan como efecto,
  en la misma transacción.

      DeliverWorker.new_for(scope, %{"event" => "feed.post_published", "post_id" => id})
  """
  use Amauta.Worker, queue: :notifications, max_attempts: 5

  alias Amauta.Notifications
  alias Amauta.Notifications.Audience

  @impl Amauta.Worker
  def perform_for(institution, %{"event" => event} = args) do
    case Audience.build(institution, event, args) do
      nil ->
        {:cancel, :gone}

      {recipients, attrs} ->
        institution
        |> Notifications.deliver(event, recipients, attrs)
        |> Notifications.after_deliver(institution)

        :ok
    end
  end

  @doc "Trabajo para entregar un evento."
  def job(tenant, event, args), do: new_for(tenant, Map.put(args, "event", event))
end
