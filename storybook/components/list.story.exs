defmodule Storybook.Components.List do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.list/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :default,
        slots: [
          ~s(<:item title="Email">ada@unsur.edu.ar</:item>),
          ~s(<:item title="Rol">Docente</:item>)
        ]
      }
    ]
  end
end
