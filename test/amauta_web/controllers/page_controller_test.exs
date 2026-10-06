defmodule AmautaWeb.PageControllerTest do
  use AmautaWeb.ConnCase, async: true

  import Amauta.PlatformFixtures

  test "sin superadministración, la portada lleva al asistente", %{conn: conn} do
    assert conn |> get(~p"/") |> redirected_to() == ~p"/setup"
  end

  test "con la instancia configurada, muestra la portada", %{conn: conn} do
    staff_fixture()

    assert conn |> get(~p"/") |> html_response(200) =~
             "Una plataforma educativa de código abierto"
  end
end
