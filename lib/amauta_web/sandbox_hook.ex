defmodule AmautaWeb.SandboxHook do
  @moduledoc """
  Solo en los tests en navegador (`config :amauta, :sql_sandbox, true`):
  la LiveView usa la transacción del test que la abrió, identificado por el
  user agent que pone Playwright (`Phoenix.Ecto.SQL.Sandbox`).
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      socket
      |> get_connect_info(:user_agent)
      |> Phoenix.Ecto.SQL.Sandbox.allow(Ecto.Adapters.SQL.Sandbox)
    end

    {:cont, socket}
  end
end
