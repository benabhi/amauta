defmodule Storybook.Components.Button do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.button/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %VariationGroup{
        id: :variants,
        description: "Variantes",
        variations:
          for variant <- ~w(primary secondary ghost danger) do
            %Variation{
              id: String.to_atom(variant),
              attributes: %{variant: variant},
              slots: ["Guardar"]
            }
          end
      },
      %VariationGroup{
        id: :sizes,
        description: "Tamaños",
        variations:
          for size <- ~w(sm md lg) do
            %Variation{id: String.to_atom(size), attributes: %{size: size}, slots: ["Entregar"]}
          end
      },
      %Variation{
        id: :with_icon,
        description: "Con ícono",
        attributes: %{icon: "plus"},
        slots: ["Nueva tarea"]
      },
      %Variation{
        id: :disabled,
        description: "Deshabilitado",
        attributes: %{disabled: true},
        slots: ["Guardar"]
      },
      %Variation{
        id: :link,
        description: "Como enlace",
        attributes: %{navigate: "/", variant: "secondary", icon: "arrow-left"},
        slots: ["Volver"]
      }
    ]
  end
end
