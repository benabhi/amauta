defmodule Storybook.Components.Tile do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.tile/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta grid max-w-xs bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{navigate: "#", icon: "path", title: "Lic. en Sistemas"},
        slots: [
          ~s(<:subtitle>LSI</:subtitle>),
          ~s(<:badge><.badge family="chilca">Publicado</.badge></:badge>)
        ]
      },
      %Variation{
        id: :minimal,
        description: "Solo título",
        attributes: %{navigate: "#", icon: "book-open", family: "anil", title: "Programación I"}
      }
    ]
  end
end
