defmodule Storybook.Components.Table do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.table/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          id: "people",
          rows: [%{name: "Ada Lovelace", grade: "9,50"}, %{name: "Beto Pérez", grade: "7,25"}]
        },
        slots: [
          ~s(<:col :let={row} label="Nombre">{row.name}</:col>),
          ~s(<:col :let={row} label="Nota">{row.grade}</:col>)
        ]
      }
    ]
  end
end
