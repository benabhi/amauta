defmodule Storybook.Components.Tabs do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.tabs/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta max-w-xl bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :course,
        description: "Pestañas fijas del curso",
        attributes: %{label: "Curso"},
        slots: [
          ~s(<:tab patch="#" icon="chats-circle" active>Tablón</:tab>),
          ~s(<:tab patch="#" icon="book-open">Contenido</:tab>),
          ~s(<:tab patch="#" icon="users">Personas</:tab>),
          ~s(<:tab patch="#" icon="clipboard-text">Calificaciones</:tab>)
        ]
      }
    ]
  end
end
