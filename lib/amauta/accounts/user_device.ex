defmodule Amauta.Accounts.UserDevice do
  @moduledoc """
  Dispositivo desde el que una persona inició sesión. Se identifica por el
  hash de su agente de usuario: alcanza para avisar de un dispositivo nuevo
  sin guardar más datos de los necesarios.
  """
  use Amauta.Schema

  schema "user_devices" do
    field :fingerprint, :binary
    field :user_agent, :string
    field :last_seen_at, :utc_datetime
    belongs_to :user, Amauta.Accounts.User

    timestamps(updated_at: false)
  end
end
