defmodule Amauta.Platform.AuditEvent do
  @moduledoc """
  Evento de la auditoría de plataforma (ERS 4.11): lo que hace el personal
  de la instancia. Inmutable: la base rechaza UPDATE y DELETE.
  """
  use Amauta.Schema

  @schema_prefix "global"
  schema "platform_audit_events" do
    field :staff_id, Ecto.UUID
    field :action, :string
    field :subject_type, :string
    field :subject_id, Ecto.UUID
    field :metadata, :map, default: %{}

    timestamps(updated_at: false)
  end
end
