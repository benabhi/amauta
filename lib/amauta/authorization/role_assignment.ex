defmodule Amauta.Authorization.RoleAssignment do
  @moduledoc """
  Persona + rol + ámbito (RF-ROL-003). El ámbito `institution` no lleva ID;
  `pathway`, `course` y `section` sí. Una asignación aplica a su ámbito y a
  todo lo que contiene.
  """
  use Amauta.Schema

  alias Amauta.Authorization.Roles

  @type t :: %__MODULE__{}

  @scope_types ~w(institution pathway course section)

  schema "role_assignments" do
    field :role, :string
    field :scope_type, :string
    field :scope_id, Ecto.UUID
    field :granted_by_id, Ecto.UUID
    field :enrollment_id, Ecto.UUID
    belongs_to :user, Amauta.Accounts.User

    timestamps(updated_at: false)
  end

  def scope_types, do: @scope_types

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:user_id, :role, :scope_type, :scope_id, :granted_by_id, :enrollment_id])
    |> validate_required([:user_id, :role, :scope_type])
    |> validate_inclusion(:role, Roles.keys())
    |> validate_inclusion(:scope_type, @scope_types)
    |> validate_scope_id()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :role, :scope_type, :scope_id],
      name: :role_assignments_unique_index,
      message: "already assigned"
    )
  end

  defp validate_scope_id(changeset) do
    case get_field(changeset, :scope_type) do
      "institution" -> put_change(changeset, :scope_id, nil)
      nil -> changeset
      _other -> validate_required(changeset, [:scope_id])
    end
  end
end
