defmodule Amauta.Accounts.Providers.Password do
  @moduledoc "Proveedor de identidad: email y contraseña (RF-AUT-001)."
  @behaviour Amauta.Accounts.IdentityProvider

  alias Amauta.Accounts

  @impl true
  def id, do: :password

  @impl true
  def authenticate(institution, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    case Accounts.get_user_by_email_and_password(institution, email, password) do
      nil -> {:error, :invalid_credentials}
      user -> {:ok, user, %{disconnect: []}}
    end
  end

  def authenticate(_institution, _params), do: {:error, :invalid_credentials}
end
