defmodule AmautaWeb.ErrorJSONTest do
  use AmautaWeb.ConnCase, async: true

  test "renders 404" do
    assert AmautaWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert AmautaWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
