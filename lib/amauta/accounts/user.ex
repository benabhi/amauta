defmodule Amauta.Accounts.User do
  @moduledoc "Persona de una institución, con sus credenciales (base: phx.gen.auth)."
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :status, :string, default: "active"

    timestamps()
  end

  @doc "Nombre para mostrar."
  def display_name(%__MODULE__{first_name: first, last_name: last}), do: "#{first} #{last}"

  @doc """
  Alta de una persona por parte de la institución (no hay autorregistro en
  el MVP). El struct debe traer el prefijo de la institución en su metadata.
  """
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name])
    |> validate_names()
    |> email_changeset(attrs)
  end

  defp validate_names(changeset) do
    changeset
    |> update_change(:first_name, &String.trim/1)
    |> update_change(:last_name, &String.trim/1)
    |> validate_required([:first_name, :last_name])
    |> validate_length(:first_name, max: 100)
    |> validate_length(:last_name, max: 100)
  end

  @doc """
  Cambio de email. Exige que el email cambie.

  ## Opciones

    * `:validate_unique` - `false` evita consultar la base, útil para la
      validación en vivo de los formularios. Por defecto, `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> update_change(:email, &String.trim/1)
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Amauta.Repo,
        prefix: Ecto.get_meta(changeset.data, :prefix)
      )
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  Cambio de contraseña (RF-AUT-001): entre 12 y 72 caracteres.

  ## Opciones

    * `:hash_password` - `false` no calcula el hash ni borra la contraseña
      en claro, útil para validar en vivo. Por defecto, `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc "Confirma la cuenta."
  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:second))
  end

  @doc """
  Verifica la contraseña. Sin persona o sin contraseña, igual consume el
  tiempo de un hash para no revelar si la cuenta existe.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end
end
