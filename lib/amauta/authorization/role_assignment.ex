defmodule Amauta.Authorization.RoleAssignment do
  @moduledoc "Persona + rol + ámbito (RF-ROL-003). Sin curso, el ámbito es la institución."
  use Ash.Resource,
    otp_app: :amauta,
    domain: Amauta.Authorization,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "role_assignments"
    repo Amauta.Repo

    references do
      reference :user, on_delete: :delete
      reference :course, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:role, :user_id, :course_id]
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end
  end

  validations do
    validate one_of(:role, Amauta.Authorization.Roles.all())
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :role, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Amauta.Accounts.User, allow_nil?: false, public?: true
    belongs_to :course, Amauta.Catalog.Course, public?: true
  end
end
