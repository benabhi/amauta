defmodule Amauta.Accounts.Providers.MagicLink do
  @moduledoc "Proveedor de identidad: enlace mágico por email (RF-AUT-002)."
  @behaviour Amauta.Accounts.IdentityProvider

  alias Amauta.Accounts

  @impl true
  def id, do: :magic_link

  @impl true
  def authenticate(institution, %{"token" => token}) when is_binary(token) do
    case Accounts.login_user_by_magic_link(institution, token) do
      {:ok, {user, expired_tokens}} -> {:ok, user, %{disconnect: expired_tokens}}
      _ -> {:error, :invalid_credentials}
    end
  end

  def authenticate(_institution, _params), do: {:error, :invalid_credentials}
end
