defmodule Storybook.Components.Kbd do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.kbd/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{id: :default, slots: ["Ctrl"]},
      %Variation{id: :letter, slots: ["K"]}
    ]
  end
end
