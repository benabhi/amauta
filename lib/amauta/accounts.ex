defmodule Amauta.Accounts do
  @moduledoc "Personas y tokens de API. Toda función recibe la institución."
  alias Amauta.Accounts.User
  alias Amauta.{Repo, Tenancy}

  def get_user(tenant, id) do
    with {:ok, id} <- Ecto.UUID.cast(id), do: Repo.get(User, id, Tenancy.opts(tenant))
  end

  def create_user(tenant, attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert(Tenancy.opts(tenant))
  end

  @doc """
  Emite un token personal. Formato: `amt_<slug>_<secreto>`; el slug permite
  resolver la institución antes de buscar a la persona (ERS 8.4).
  Solo se guarda el hash del secreto.
  """
  def generate_api_token(%{slug: slug} = institution, %User{} = user) do
    secret = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    user
    |> Ecto.Changeset.change(api_token_hash: hash(secret))
    |> Repo.update!(Tenancy.opts(institution))

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
    Repo.get_by(User, [api_token_hash: hash(secret)], Tenancy.opts(tenant))
  end

  defp hash(secret), do: :crypto.hash(:sha256, secret)
end
