defmodule Amauta.Accounts do
  @moduledoc "Personas y tokens de API."
  use Ash.Domain, otp_app: :amauta

  alias Amauta.Accounts.User

  resources do
    resource User do
      define :create_user, action: :create
      define :get_user, action: :read, get_by: [:id], not_found_error?: false
    end
  end

  @doc """
  Emite un token personal. Formato: `amt_<slug>_<secreto>`; el slug permite
  resolver la institución antes de buscar a la persona (ERS 8.4).
  Solo se guarda el hash del secreto.
  """
  def generate_api_token(%{slug: slug} = institution, %User{} = user) do
    secret = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    user
    |> Ash.Changeset.for_update(:set_api_token_hash, %{api_token_hash: hash(secret)},
      tenant: institution,
      authorize?: false
    )
    |> Ash.update!()

    "amt_#{slug}_#{secret}"
  end

  @doc "Separa un token en `{slug, secreto}`."
  def parse_api_token("amt_" <> rest) do
    case String.split(rest, "_", parts: 2) do
      [slug, secret] when slug != "" and secret != "" -> {:ok, slug, secret}
      _ -> :error
    end
  end

  def parse_api_token(_), do: :error

  def get_user_by_api_secret(tenant, secret) do
    User
    |> Ash.Query.for_read(:by_api_token_hash, %{api_token_hash: hash(secret)}, tenant: tenant)
    |> Ash.read_one!(authorize?: false)
  end

  defp hash(secret), do: :crypto.hash(:sha256, secret)
end
