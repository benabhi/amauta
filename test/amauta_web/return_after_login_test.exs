defmodule AmautaWeb.ReturnAfterLoginTest do
  @moduledoc """
  Volver a la página pedida después de entrar. Bug: Ajustes pedía volver a
  autenticarse y, al entrar, se terminaba en el inicio.
  """
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures

  alias AmautaWeb.{Paths, UserAuth}

  defp old_session(conn, user) do
    log_in_user(conn, user,
      token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    )
  end

  test "después de volver a entrar, vuelve a Ajustes", %{conn: conn} do
    user = user_fixture() |> set_password()
    conn = old_session(conn, user)
    settings = Paths.settings(institution())

    {:error, {:redirect, %{to: login}}} = live(conn, settings)
    assert login == Paths.log_in_return(institution(), settings)

    {:ok, view, _html} = live(conn, login)

    assert has_element?(
             view,
             ~s(#login_form_password input[name="user[return_to]"][value="#{settings}"])
           )

    conn =
      post(conn, Paths.log_in(institution()), %{
        "user" => %{
          "email" => user.email,
          "password" => valid_user_password(),
          "return_to" => settings
        }
      })

    assert redirected_to(conn) == settings
  end

  test "no redirige fuera de la institución", %{conn: conn} do
    user = user_fixture() |> set_password()

    for evil <- [
          "https://otro.sitio/robo",
          "//otro.sitio/robo",
          "/otra-institucion/settings",
          "/#{institution().slug}//otro.sitio"
        ] do
      conn =
        post(conn, Paths.log_in(institution()), %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "return_to" => evil
          }
        })

      assert redirected_to(conn) == Paths.home(institution())
    end
  end

  test "safe_return_to/2 solo acepta rutas internas de la institución" do
    slug = institution().slug
    assert UserAuth.safe_return_to(institution(), "/#{slug}/settings") == "/#{slug}/settings"
    assert is_nil(UserAuth.safe_return_to(institution(), "/#{slug}"))
    assert is_nil(UserAuth.safe_return_to(institution(), "/otra/settings"))
    assert is_nil(UserAuth.safe_return_to(institution(), "https://#{slug}.evil/x"))
    assert is_nil(UserAuth.safe_return_to(institution(), nil))
  end
end
