defmodule Storybook.Components.AttachmentList do
  use PhoenixStorybook.Story, :component

  alias Amauta.Files.StoredFile

  def function, do: &AmautaWeb.CoreComponents.attachment_list/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta bg-paper p-4 font-sans text-ink max-w-prose"}

  defp file(name, type, size),
    do: %StoredFile{id: Ecto.UUID.generate(), filename: name, content_type: type, size: size}

  defp files do
    [
      file("programa.pdf", "application/pdf", 245_000),
      file(
        "cronograma.xlsx",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        31_200
      ),
      file("clase-1.mp4", "video/mp4", 48_500_000),
      file("entrevista.mp3", "audio/mpeg", 3_400_000),
      file("pizarron.png", "image/png", 820_000)
    ]
  end

  defp tenant, do: %Amauta.Platform.Institution{slug: "demo"}

  def variations do
    [
      %Variation{
        id: :default,
        description: "Documentos con vista previa o descarga; las imágenes, como miniaturas",
        attributes: %{id: "attachments-default", files: files(), tenant: tenant()}
      },
      %Variation{
        id: :removable,
        description: "Mientras se escribe: cada archivo se puede quitar",
        attributes: %{
          id: "attachments-removable",
          files: Enum.take(files(), 2),
          tenant: tenant(),
          remove: "remove_file"
        }
      }
    ]
  end
end
