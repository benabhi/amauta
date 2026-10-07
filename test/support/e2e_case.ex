defmodule AmautaWeb.E2ECase do
  @moduledoc """
  Pruebas en navegador real (Playwright), con la institución del test.
  Se corren aparte con `bin/dev e2e` (`mix test --only e2e`).

  `log_in/2` entra con una cookie de sesión, como los tests de LiveView: el
  formulario de login ya está cubierto por sus propios tests, y pasar por
  él en cada prueba la hacía lenta y frágil en la CI.
  """
  defmacro __using__(_opts) do
    quote do
      use PhoenixTest.Playwright.Case, async: true

      import Amauta.AccountsFixtures
      import Amauta.AuthorizationFixtures
      import AmautaWeb.E2ECase

      @moduletag :e2e
    end
  end

  import Amauta.AccountsFixtures
  import PhoenixTest.Playwright

  alias AmautaWeb.{Paths, UserAuth}

  @doc """
  Inicia la sesión de la persona, abre `path` y espera a que su LiveView
  esté conectada (si se interactúa antes, LiveView vuelve a dibujar la
  página al conectar).
  """
  def log_in(conn, user, path \\ nil) do
    token = Amauta.Accounts.generate_user_session_token(institution(), user)

    conn
    |> add_session_cookie(
      [value: %{UserAuth.session_token_key(institution()) => token}],
      AmautaWeb.Endpoint.session_options()
    )
    |> visit(path || Paths.home(institution()))
    |> wait_connected()
  end

  @doc "Espera a que la LiveView de la página esté conectada."
  def wait_connected(conn), do: assert_has(conn, "[data-phx-main].phx-connected")
end
