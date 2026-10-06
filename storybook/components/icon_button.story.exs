defmodule Storybook.Components.IconButton do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.icon_button/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{id: :ghost, attributes: %{icon: "bell", label: "Notificaciones"}},
      %Variation{
        id: :secondary,
        attributes: %{icon: "gear", label: "Ajustes", variant: "secondary"}
      },
      %Variation{id: :danger, attributes: %{icon: "trash", label: "Borrar", variant: "danger"}}
    ]
  end
end
