defmodule Amauta.Accounts.User do
  @moduledoc "Persona de una institución."
  use Ash.Resource,
    otp_app: :amauta,
    domain: Amauta.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  # Solo se expone el nombre: el email es un dato personal (RF-ROL-008).
  json_api do
    type "user"
    default_fields [:name]
  end

  postgres do
    table "users"
    repo Amauta.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :email]
    end

    update :set_api_token_hash do
      accept [:api_token_hash]
      # La validación de formato del email no se puede expresar en SQL.
      require_atomic? false
    end

    read :by_api_token_hash do
      argument :api_token_hash, :binary, allow_nil?: false
      get? true
      filter expr(api_token_hash == ^arg(:api_token_hash))
    end
  end

  validations do
    validate match(:email, ~r/^[^@\s]+@[^@\s]+$/)
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    # No público: así no lo expone la API aunque el cliente lo pida.
    attribute :email, :string, allow_nil?: false
    attribute :api_token_hash, :binary, sensitive?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_api_token_hash, [:api_token_hash]
  end
end
