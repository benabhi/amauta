defmodule Storybook.Components.RichTextEditor do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.rich_text_editor/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta max-w-2xl bg-paper p-4 pb-64 font-sans text-ink"}

  # Probá escribir «/» para ver el menú de bloques.
  def variations do
    form = Phoenix.Component.to_form(%{"description" => nil}, as: "demo")

    [
      %Variation{
        id: :empty,
        description: "Vacío",
        attributes: %{field: form[:description], label: "Descripción"}
      }
    ]
  end
end
