defmodule Amauta.PubSub.Ash do
  @moduledoc """
  Adaptador para `Ash.Notifier.PubSub`: publica en `Amauta.PubSub` la
  notificación completa, sin pasar por el Endpoint.
  """
  def broadcast(topic, event, notification) do
    Phoenix.PubSub.broadcast(Amauta.PubSub, topic, {event, notification})
  end
end
