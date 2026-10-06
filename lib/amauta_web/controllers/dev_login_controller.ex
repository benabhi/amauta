defmodule AmautaWeb.DevLoginController do
  @moduledoc "Inicio de sesión rápido, solo en desarrollo y tests (RNF-DEV-009)."
  use AmautaWeb, :controller
  alias Amauta.Accounts
  alias AmautaWeb.Plugs.Tenant

  def create(conn, %{"user_id" => user_id} = params) do
    institution = conn.assigns.current_scope.institution

    user =
      Accounts.get_user!(user_id, tenant: institution, authorize?: false) ||
        raise AmautaWeb.NotFoundError

    conn
    |> put_session(Tenant.session_key(institution), user.id)
    |> redirect(to: safe_path(params["to"]))
  end

  # Solo rutas locales, para no abrir una redirección arbitraria.
  defp safe_path("//" <> _), do: "/"
  defp safe_path("/" <> _ = path), do: path
  defp safe_path(_), do: "/"
end
