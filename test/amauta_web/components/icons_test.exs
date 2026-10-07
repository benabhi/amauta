defmodule AmautaWeb.Components.IconsTest do
  use ExUnit.Case, async: true

  # Los estados vacíos usan la variante duotone del ícono, que tiene que
  # estar en el sprite; si falta, el recuadro se ve sin ícono.
  @sprite File.read!("priv/static/images/icons.svg")

  test "cada ícono de un estado vacío tiene su variante duotone en el sprite" do
    icons =
      Path.wildcard("lib/**/*.{ex,heex}")
      |> Enum.flat_map(fn path ->
        Regex.scan(~r/<\.empty_state\s+icon="([a-z-]+)"/, File.read!(path),
          capture: :all_but_first
        )
      end)
      |> List.flatten()
      |> Enum.uniq()

    assert "clipboard-text" in icons

    for icon <- ["folder-open" | icons] do
      assert @sprite =~ ~s(id="#{icon}-duotone"), "falta #{icon}-duotone en el sprite"
    end
  end
end
