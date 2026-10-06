defmodule AmautaWeb.ScopeHook do
  @moduledoc "Arma el Scope de las LiveViews con las mismas reglas que el plug."
  import Phoenix.Component
  alias Amauta.{Accounts, Platform, Scope}
  alias AmautaWeb.Plugs.Tenant

  def on_mount(:default, %{"institution" => slug}, session, socket) do
    socket =
      assign_new(socket, :current_scope, fn ->
        institution = Platform.get_institution_by_slug(slug) || raise AmautaWeb.NotFoundError
        user_id = session[Tenant.session_key(institution)]
        Scope.for_user(institution, user_id && Accounts.get_user(institution, user_id))
      end)

    {:cont, socket}
  end
end
