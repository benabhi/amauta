defmodule Storybook.Components.Collapsible do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.collapsible/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink max-w-prose"}

  @long Enum.map_join(1..14, "", fn i ->
          "<p class=\"mb-3\">Párrafo #{i} de un programa de la materia: objetivos, contenidos, bibliografía y criterios de evaluación.</p>"
        end)

  def variations do
    [
      %Variation{
        id: :long,
        description: "Contenido largo: se recorta con desvanecido y aparece «Ver más»",
        attributes: %{id: "collapsible-long"},
        slots: [@long]
      },
      %Variation{
        id: :short,
        description: "Contenido corto: se ve entero y sin botón",
        attributes: %{id: "collapsible-short"},
        slots: ["<p>Mañana no hay clase.</p>"]
      }
    ]
  end
end
