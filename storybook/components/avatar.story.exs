defmodule Storybook.Components.Avatar do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.avatar/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %VariationGroup{
        id: :sizes,
        description: "Tamaños",
        variations:
          for size <- ~w(sm md lg) do
            %Variation{id: String.to_atom(size), attributes: %{name: "Ada Lovelace", size: size}}
          end
      },
      %VariationGroup{
        id: :people,
        description: "Cada persona conserva su color",
        variations:
          for name <- ["Ada Lovelace", "Beto Pérez", "Carla Quispe", "Diego Mamani"] do
            %Variation{
              id: String.to_atom(String.replace(name, " ", "_")),
              attributes: %{name: name}
            }
          end
      },
      %Variation{
        id: :broken_photo,
        description: "Foto que no carga: quedan las iniciales",
        attributes: %{name: "Carla Administración", src: "/no-existe.png", size: "md"}
      }
    ]
  end
end
