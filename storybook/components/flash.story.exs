defmodule Storybook.Components.Flash do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.flash/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink"}

  def variations do
    [
      %Variation{
        id: :info,
        attributes: %{kind: :info, id: "flash-info"},
        slots: ["Cambiaste tu contraseña."]
      },
      %Variation{
        id: :error,
        attributes: %{kind: :error, id: "flash-error", title: "No se pudo guardar"},
        slots: ["Revisá los campos marcados."]
      }
    ]
  end
end
