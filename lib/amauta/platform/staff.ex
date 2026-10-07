defmodule Amauta.Platform.Staff do
  @moduledoc """
  Personal de la instancia (RF-ROL-009). En el MVP, solo la
  superadministración. No es persona de ninguna institución.
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "global"
  schema "platform_staff" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :role, :string, default: "superadmin"

    timestamps()
  end

  def registration_changeset(staff, attrs) do
    staff
    |> cast(attrs, [:name, :email, :password])
    |> update_change(:name, &String.trim/1)
    |> update_change(:email, &String.trim/1)
    |> validate_required([:name, :email, :password])
    |> validate_length(:name, max: 120)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Amauta.Repo)
    |> unique_constraint(:email)
    |> validate_length(:password, min: 12, max: 72)
    |> hash_password()
  end

  defp hash_password(%{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset

  @doc "Verifica la contraseña sin revelar si la cuenta existe."
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and byte_size(password) > 0,
      do: Argon2.verify_pass(password, hash)

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end
end
