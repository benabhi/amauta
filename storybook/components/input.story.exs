defmodule Storybook.Components.Input do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.input/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{id: :text, attributes: %{name: "name", label: "Nombre", value: "Ada"}},
      %Variation{
        id: :hint,
        description: "Con ayuda",
        attributes: %{
          name: "email",
          type: "email",
          label: "Email",
          hint: "Usá tu email institucional."
        }
      },
      %Variation{
        id: :error,
        description: "Con error",
        attributes: %{
          name: "email",
          type: "email",
          label: "Email",
          value: "ada",
          errors: ["tiene que tener una @"]
        }
      },
      %Variation{id: :textarea, attributes: %{name: "body", type: "textarea", label: "Mensaje"}},
      %Variation{
        id: :select,
        attributes: %{
          name: "role",
          type: "select",
          label: "Rol",
          options: ["Docente", "Estudiante"],
          prompt: "Elegí un rol"
        }
      },
      %Variation{
        id: :checkbox,
        attributes: %{name: "remember", type: "checkbox", label: "Recordarme"}
      }
    ]
  end
end
