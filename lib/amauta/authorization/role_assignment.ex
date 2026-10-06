defmodule Amauta.Authorization.RoleAssignment do
  @moduledoc "Persona + rol + ámbito (RF-ROL-003). Sin curso, el ámbito es la institución."
  use Amauta.Schema
  alias Amauta.Authorization.Roles

  schema "role_assignments" do
    field :role, :string
    belongs_to :user, Amauta.Accounts.User
    belongs_to :course, Amauta.Catalog.Course

    timestamps()
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:role, :user_id, :course_id])
    |> validate_required([:role, :user_id])
    |> validate_inclusion(:role, Roles.all())
  end
end
