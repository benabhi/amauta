defmodule Amauta.Platform.StaffAccounts do
  @moduledoc """
  Cuentas y sesiones del personal de plataforma (RF-ROL-009), en el schema
  global. Entran solo con contraseña: no dependen del SMTP de la instancia.
  """
  import Ecto.Query

  alias Amauta.Platform.{Staff, StaffToken}
  alias Amauta.Repo

  @doc """
  El asistente de primera ejecución hace falta mientras no exista ninguna
  cuenta de superadministración (RF-ADM-001).
  """
  @spec setup_required?() :: boolean()
  def setup_required?, do: not Repo.exists?(from(s in Staff, where: s.role == "superadmin"))

  @doc """
  Crea la primera superadministración. Falla si ya existe una: después del
  asistente, el personal se agrega desde la administración (V1).
  """
  def create_first_superadmin(attrs) do
    Repo.transact(fn ->
      # Serializa el asistente para que dos personas no lo completen a la vez.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('amauta:setup'))")

      if setup_required?() do
        %Staff{role: "superadmin"} |> Staff.registration_changeset(attrs) |> Repo.insert()
      else
        {:error, :already_set_up}
      end
    end)
  end

  def change_registration(attrs \\ %{}), do: Staff.registration_changeset(%Staff{}, attrs)

  @doc "Personal por email y contraseña, o `nil`."
  def get_staff_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    staff = Repo.get_by(Staff, email: String.trim(email))
    if Staff.valid_password?(staff, password), do: staff
  end

  def generate_session_token(%Staff{} = staff) do
    {token, record} = StaffToken.build_session_token(staff)
    Repo.insert!(record)
    token
  end

  def get_staff_by_session_token(token) when is_binary(token) do
    token |> StaffToken.verify_session_token_query() |> Repo.one()
  end

  def delete_session_token(token) when is_binary(token) do
    Repo.delete_all(from(t in StaffToken, where: t.token == ^token and t.context == "session"))
    :ok
  end
end
