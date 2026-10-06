defmodule AmautaWeb.Plugs.ApiAuth do
  @moduledoc """
  Autenticación de la API con token personal. La institución se determina
  a partir del token, no de la URL (ERS 8.4).
  """
  import Plug.Conn
  alias Amauta.{Accounts, Platform, Scope}

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, slug, secret} <- Accounts.parse_api_token(token),
         %{} = institution <- Platform.get_institution_by_slug(slug),
         %{} = user <- Accounts.get_user_by_api_secret(institution, secret) do
      assign(conn, :current_scope, Scope.for_user(institution, user))
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{errors: %{detail: "Unauthorized"}})
        |> halt()
    end
  end
end
