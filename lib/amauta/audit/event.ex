defmodule Amauta.Audit.Event do
  @moduledoc "Evento de auditoría inmutable (solo se insertan)."
  use Amauta.Schema

  schema "audit_events" do
    field :actor_id, Ecto.UUID
    field :action, :string
    field :subject_type, :string
    field :subject_id, Ecto.UUID
    field :metadata, :map, default: %{}

    timestamps(updated_at: false)
  end
end
