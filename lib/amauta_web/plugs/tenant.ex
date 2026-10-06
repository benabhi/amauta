defmodule AmautaWeb.Plugs.Tenant do
  @moduledoc """
  Resuelve la institución a partir de la ruta (modo ruta) y arma el Scope
  con la persona de la sesión. La sesión guarda una persona por institución.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"institution" => slug}} = conn, _opts) do
    scope = AmautaWeb.ScopeHook.build_scope(slug, get_session(conn))
    assign(conn, :current_scope, scope)
  end

  def session_key(institution), do: "user_id:#{institution.id}"
end
