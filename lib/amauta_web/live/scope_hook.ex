defmodule AmautaWeb.ScopeHook do
  @moduledoc "Arma el Scope de las LiveViews con las mismas reglas que el plug."
  import Phoenix.Component
  alias Amauta.{Accounts, Platform, Scope}
  alias AmautaWeb.Plugs.Tenant

  def on_mount(:default, %{"institution" => slug}, session, socket) do
    {:cont, assign_new(socket, :current_scope, fn -> build_scope(slug, session) end)}
  end

  def build_scope(slug, session) do
    institution = Platform.get_institution_by_slug!(slug) || raise AmautaWeb.NotFoundError

    Scope.for_user(
      institution,
      session_user(institution, session[Tenant.session_key(institution)])
    )
  end

  defp session_user(_institution, nil), do: nil

  defp session_user(institution, user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, id} -> Accounts.get_user!(id, tenant: institution, authorize?: false)
      :error -> nil
    end
  end
end
