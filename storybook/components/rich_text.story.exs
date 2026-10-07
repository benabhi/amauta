defmodule Storybook.Components.RichText do
  use PhoenixStorybook.Story, :component

  def function, do: &AmautaWeb.CoreComponents.rich_text/1
  def render_source, do: :function
  def container, do: {:div, class: "amauta max-w-prose bg-paper p-4 font-sans text-ink"}

  @doc_example %{
    "type" => "doc",
    "content" => [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 2},
        "content" => [%{"type" => "text", "text" => "Unidad 1 · Variables"}]
      },
      %{
        "type" => "paragraph",
        "content" => [
          %{"type" => "text", "text" => "Una variable guarda un "},
          %{"type" => "text", "text" => "valor", "marks" => [%{"type" => "bold"}]},
          %{"type" => "text", "text" => "."}
        ]
      },
      %{
        "type" => "callout",
        "attrs" => %{"tone" => "warning"},
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "El nombre distingue mayúsculas."}]
          }
        ]
      },
      %{
        "type" => "codeBlock",
        "attrs" => %{"language" => "python"},
        "content" => [%{"type" => "text", "text" => "edad = 18\nprint(edad)"}]
      },
      %{"type" => "mathBlock", "attrs" => %{"latex" => "a^2 + b^2 = c^2"}}
    ]
  }

  def variations do
    [
      %Variation{
        id: :page,
        description: "Página publicada",
        attributes: %{id: "story-rich-text", doc: @doc_example}
      }
    ]
  end
end
