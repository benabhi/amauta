defmodule Storybook.Components.Dropdown do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.dropdown/1
  def render_source, do: :function

  def container,
    do: {:div, class: "amauta flex justify-end bg-paper p-4 pb-48 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :account,
        description: "Menú de la cuenta",
        attributes: %{id: "story-dropdown", label: "Menú de la cuenta"},
        slots: [
          ~s(<:trigger><.avatar name="Ana Pérez" size="sm" /></:trigger>),
          ~s(<.dropdown_item href="#" icon="gear">Ajustes de la cuenta</.dropdown_item>),
          ~s(<.dropdown_item href="#" icon="sign-out">Salir</.dropdown_item>)
        ]
      }
    ]
  end
end
