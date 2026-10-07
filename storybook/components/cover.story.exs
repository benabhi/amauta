defmodule Storybook.Components.Cover do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.cover/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta grid max-w-md gap-4 bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %VariationGroup{
        id: :families,
        description: "Una semilla distinta por familia",
        variations:
          for family <- AmautaWeb.CoreComponents.families() do
            %Variation{
              id: String.to_atom(family),
              attributes: %{
                seed: "curso-#{family}",
                family: family,
                icon: "book-open",
                class: "h-28"
              }
            }
          end
      },
      %Variation{
        id: :without_icon,
        description: "Sin ícono",
        attributes: %{seed: "programacion-1", family: "airampo", class: "h-28"}
      }
    ]
  end
end
