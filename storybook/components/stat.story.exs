defmodule Storybook.Components.Stat do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.stat/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta grid max-w-xs gap-4 bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :with_detail,
        description: "Con ícono, enlace y detalle",
        attributes: %{value: "128", label: "Personas activas", icon: "users", navigate: "#"},
        slots: ["<:detail>12 con la invitación pendiente</:detail>"]
      },
      %Variation{
        id: :plain,
        description: "Solo el número",
        attributes: %{value: "4", label: "Cursos publicados", family: "chilca"}
      }
    ]
  end
end
