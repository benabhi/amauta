defmodule AmautaWeb.Components.AvatarTest do
  @moduledoc "Avatar: iniciales, foto y nombre accesible."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AmautaWeb.CoreComponents

  test "sin foto muestra las iniciales y el nombre para lectores de pantalla" do
    html = render_component(&CoreComponents.avatar/1, name: "Carla Administración")

    assert html =~ ">CA<"
    assert html =~ ~s(<span class="sr-only">Carla Administración</span>)
    refute html =~ "<img"
  end

  test "con foto conserva las iniciales debajo, por si la foto no carga" do
    html =
      render_component(&CoreComponents.avatar/1,
        name: "Carla Administración",
        src: "/unsur/files/abc"
      )

    # Antes, una foto que no cargaba mostraba el texto alternativo cortado
    # («Carla Adm») en lugar de las iniciales.
    assert html =~ ">CA<"
    assert html =~ ~s(alt="")
    refute html =~ ~s(alt="Carla Administración")
    assert html =~ ~s(<span class="sr-only">Carla Administración</span>)
  end
end
