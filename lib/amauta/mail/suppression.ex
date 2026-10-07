defmodule Amauta.Mail.Suppression do
  @moduledoc """
  Dirección con fallos permanentes de entrega (RF-EML-003). Al llegar a
  `Amauta.Mail.max_bounces/0` rebotes queda suprimida: no se le envía más.
  """
  use Amauta.Schema

  @schema_prefix "global"

  @type t :: %__MODULE__{}

  schema "email_suppressions" do
    field :address, :string
    field :bounces, :integer, default: 0
    field :last_error, :string
    field :suppressed_at, :utc_datetime_usec

    timestamps()
  end
end
