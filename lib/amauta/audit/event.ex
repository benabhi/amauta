defmodule Amauta.Audit.Event do
  @moduledoc """
  Evento de auditoría de una institución. Es inmutable: la base rechaza
  cualquier UPDATE o DELETE (trigger `audit_events_immutable`), y la cadena
  de hashes delata cualquier alteración (ver `Amauta.Audit`).
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "audit_events" do
    field :actor_id, Ecto.UUID
    field :action, :string
    field :subject_type, :string
    field :subject_id, Ecto.UUID
    field :metadata, :map, default: %{}
    field :sequence, :integer
    field :prev_hash, :binary
    field :hash, :binary

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :action, :subject_type, :subject_id, :metadata])
    |> validate_required([:action])
    |> validate_format(:action, ~r/^[a-z_]+(\.[a-z_]+)+$/)
  end
end
