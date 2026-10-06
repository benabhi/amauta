defmodule Amauta.Catalog.Course do
  @moduledoc "Curso de una institución."
  use Ash.Resource,
    otp_app: :amauta,
    domain: Amauta.Catalog,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "courses"
    repo Amauta.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:slug, :name]
    end

    read :by_slug do
      get_by :slug
    end
  end

  validations do
    validate match(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
