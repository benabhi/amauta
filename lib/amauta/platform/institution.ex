defmodule Amauta.Platform.Institution do
  @moduledoc """
  Institución registrada en el schema global. Al crearla, AshPostgres crea
  su schema y le aplica las migraciones de institución (`manage_tenant`).
  """
  use Ash.Resource,
    otp_app: :amauta,
    domain: Amauta.Platform,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "institutions"
    schema "global"
    repo Amauta.Repo

    manage_tenant do
      template [:schema_name]
      create? true
      update? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:slug, :name, :schema_name]

      change fn changeset, _ctx ->
        if Ash.Changeset.get_attribute(changeset, :schema_name) do
          changeset
        else
          suffix = :crypto.strong_rand_bytes(5) |> Base.encode32(case: :lower, padding: false)
          Ash.Changeset.force_change_attribute(changeset, :schema_name, "inst_" <> suffix)
        end
      end
    end

    read :by_slug do
      get_by :slug
    end
  end

  validations do
    validate match(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    validate match(:schema_name, ~r/^inst_[a-z0-9_]+$/)
    validate {Amauta.Platform.Validations.NotReserved, attribute: :slug}
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :schema_name, :string, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_schema_name, [:schema_name]
  end
end

defimpl Ash.ToTenant, for: Amauta.Platform.Institution do
  def to_tenant(%{schema_name: schema_name}, _resource), do: schema_name
end
