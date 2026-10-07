defmodule Storybook.Components.CopyButton do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.copy_button/1
  def render_source, do: :function

  def container,
    do: {:div, class: "amauta flex items-center gap-2 bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :code,
        description: "Al lado de un código",
        attributes: %{value: "YK6GG54", label: "Copiar el código de inscripción"}
      }
    ]
  end
end
