defmodule Storybook.Components.Divider do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.divider/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{id: :plain},
      %Variation{id: :with_label, description: "Con texto", slots: ["o"]}
    ]
  end
end
