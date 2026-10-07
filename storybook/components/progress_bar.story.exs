defmodule Storybook.Components.ProgressBar do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.progress_bar/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink w-64"}

  def variations do
    [
      %Variation{
        id: :empty,
        description: "Sin avance",
        attributes: %{value: 0, max: 4, label: "0 de 4 hechos"}
      },
      %Variation{
        id: :half,
        description: "A mitad",
        attributes: %{value: 2, max: 4, label: "2 de 4 hechos"}
      },
      %Variation{
        id: :full,
        description: "Completo",
        attributes: %{value: 4, max: 4, label: "4 de 4 hechos"}
      }
    ]
  end
end
