defmodule AmautaWeb.PageControllerTest do
  use AmautaWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Una plataforma educativa de código abierto"
  end
end
