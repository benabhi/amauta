defmodule Storybook.Components.DirectUpload do
  use PhoenixStorybook.Story, :live_component

  def component, do: AmautaWeb.Components.DirectUpload
  def container, do: {:div, class: "amauta max-w-md bg-paper p-4 font-sans text-ink"}

  # En el catálogo no hay sesión: se ve la zona de subida y sus textos; la
  # subida real se prueba en Ajustes de la cuenta.
  def variations do
    [
      %Variation{
        id: :avatar,
        description: "Foto de perfil",
        attributes: %{
          current_scope: nil,
          purpose: "avatar",
          accept: "image/png,image/jpeg,image/gif,image/webp",
          label: "Subí una foto",
          hint: "PNG, JPG, GIF o WebP, hasta 5 MB."
        }
      }
    ]
  end
end
