defmodule Storybook.Components.EmptyState do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.empty_state/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{icon: "book-open", title: "Todavía no tenés cursos"},
        slots: ["Cuando te sumes a una clase, la vas a encontrar acá."]
      },
      %Variation{
        id: :with_action,
        description: "Con acción",
        attributes: %{icon: "folder-open", title: "No hay materiales"},
        slots: [
          "Subí el primer archivo de la unidad.",
          ~s(<:action><.button icon="upload-simple">Subir</.button></:action>)
        ]
      }
    ]
  end
end
