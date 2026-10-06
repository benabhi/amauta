defmodule AmautaWeb.Plugs.Tenant do
  @moduledoc """
  Resuelve la institución a partir de la ruta (modo ruta) y arma el Scope
  con la persona de la sesión. La sesión guarda una persona por institución.
  """
  import Plug.Conn
  alias Amauta.{Accounts, Platform, Scope}

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"institution" => slug}} = conn, _opts) do
    institution = Platform.get_institution_by_slug(slug) || raise AmautaWeb.NotFoundError
    user_id = get_session(conn, session_key(institution))
    user = user_id && Accounts.get_user(institution, user_id)

    assign(conn, :current_scope, Scope.for_user(institution, user))
  end

  def session_key(institution), do: "user_id:#{institution.id}"
end
