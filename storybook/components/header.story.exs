defmodule Storybook.Components.Header do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.header/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{id: :default, slots: ["Programación I"]},
      %Variation{
        id: :full,
        description: "Con subtítulo y acciones",
        slots: [
          "Programación I",
          "<:subtitle>Primer cuatrimestre 2027</:subtitle>",
          ~s(<:actions><.button variant="secondary" icon="gear">Ajustes</.button></:actions>)
        ]
      }
    ]
  end
end
