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
    field :status, :string, default: "invited"
    field :locale, :string
    field :preferred_name, :string
    field :timezone, :string
    field :invited_at, :utc_datetime

    timestamps()
  end

  @statuses ~w(invited active suspended archived)

  @doc "Estados de cuenta (RF-USR-003)."
  def statuses, do: @statuses

  @doc "Nombre para mostrar: el preferido, si lo hay, y el apellido."
  def display_name(%__MODULE__{preferred_name: preferred, last_name: last})
      when is_binary(preferred) and preferred != "",
      do: "#{preferred} #{last}"

  def display_name(%__MODULE__{first_name: first, last_name: last}), do: "#{first} #{last}"

  @doc "Nombre de pila para saludar."
  def given_name(%__MODULE__{preferred_name: preferred})
      when is_binary(preferred) and preferred != "",
      do: preferred

  def given_name(%__MODULE__{first_name: first}), do: first

  @doc """
  Alta de una persona por parte de la institución (no hay autorregistro en
  el MVP). El struct debe traer el prefijo de la institución en su metadata.
  """
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name, :preferred_name, :timezone])
    |> validate_names()
    |> validate_timezone()
    |> email_changeset(attrs)
  end

  @doc "Edición del perfil por la institución o por la persona (sin el email)."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name, :preferred_name, :timezone, :locale])
    |> validate_names()
    |> validate_timezone()
    |> validate_inclusion(:locale, Amauta.Locale.supported())
  end

  @doc "Cambio de estado."
  def status_changeset(user, status) do
    user |> change(status: status) |> validate_inclusion(:status, @statuses)
  end

  defp validate_timezone(changeset) do
    changeset
    |> update_change(:timezone, &blank_to_nil/1)
    |> validate_inclusion(:timezone, Tzdata.zone_list())
  end

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp blank_to_nil(value), do: value

  defp validate_names(changeset) do
    changeset
    |> update_change(:first_name, &String.trim/1)
    |> update_change(:last_name, &String.trim/1)
    |> update_change(:preferred_name, &blank_to_nil/1)
    |> validate_required([:first_name, :last_name])
    |> validate_length(:first_name, max: 100)
    |> validate_length(:last_name, max: 100)
    |> validate_length(:preferred_name, max: 100)
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
    status = if user.status == "invited", do: "active", else: user.status
    change(user, confirmed_at: DateTime.utc_now(:second), status: status)
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
