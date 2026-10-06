defmodule Storybook.Components.Badge do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.badge/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %VariationGroup{
        id: :families,
        description: "Familias",
        variations:
          for family <- AmautaWeb.CoreComponents.families() do
            %Variation{id: String.to_atom(family), attributes: %{family: family}, slots: [family]}
          end
      },
      %Variation{
        id: :with_icon,
        description: "Con ícono",
        attributes: %{family: "chilca", icon: "check"},
        slots: ["Entregado"]
      }
    ]
  end
end
