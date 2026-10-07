defmodule Amauta.Notifications.Preference do
  @moduledoc """
  Si una persona quiere un evento por un canal (RF-NOT-004, RF-EML-005).
  Sin fila, vale el valor por defecto de la instancia
  (`Amauta.Notifications.Catalog`).
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "notification_preferences" do
    field :event, :string
    field :channel, :string
    field :enabled, :boolean

    belongs_to :user, Amauta.Accounts.User

    timestamps()
  end
end
