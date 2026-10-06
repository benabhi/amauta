defmodule Amauta.Audit.Event do
  @moduledoc "Evento de auditoría inmutable (solo se insertan)."
  use Ash.Resource,
    otp_app: :amauta,
    domain: Amauta.Audit,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "audit_events"
    repo Amauta.Repo

    custom_indexes do
      index [:subject_type, :subject_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:actor_id, :action, :subject_type, :subject_id, :metadata]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :actor_id, :uuid, public?: true
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :subject_type, :string, public?: true
    attribute :subject_id, :uuid, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true
    create_timestamp :inserted_at, public?: true
  end
end
