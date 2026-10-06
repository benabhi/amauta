defmodule Storybook.Components.Card do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.card/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :default,
        slots: [~s(<:header>Programación I</:header>), "Primer cuatrimestre · Comisión B"]
      },
      %Variation{
        id: :with_footer,
        description: "Con pie",
        slots: [
          ~s(<:header>Tarea 2</:header>),
          "Vence el viernes a las 23:59.",
          ~s(<:footer><span class="text-sm text-ink-muted">3 de 25 entregas</span></:footer>)
        ]
      }
    ]
  end
end
