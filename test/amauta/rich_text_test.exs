defmodule Amauta.RichTextTest do
  @moduledoc "Contenido enriquecido: depuración, HTML seguro y texto plano (RF-CON-003, ERS 8.13)."
  use ExUnit.Case, async: true

  alias Amauta.RichText
  alias Amauta.RichText.Document

  defp doc(content), do: %{"type" => "doc", "content" => content}
  defp p(content), do: %{"type" => "paragraph", "content" => content}
  defp t(text, marks \\ []), do: %{"type" => "text", "text" => text, "marks" => marks}
  defp html(doc), do: doc |> RichText.to_html() |> Phoenix.HTML.safe_to_string()

  defp clean!(doc) do
    {:ok, doc} = RichText.sanitize(doc)
    doc
  end

  describe "depuración" do
    test "conserva los bloques y marcas permitidos" do
      input =
        doc([
          %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [t("Unidad 1")]},
          p([t("Hola "), t("mundo", [%{"type" => "bold"}, %{"type" => "italic"}])]),
          %{"type" => "callout", "attrs" => %{"tone" => "warning"}, "content" => [p([t("Ojo")])]},
          %{
            "type" => "codeBlock",
            "attrs" => %{"language" => "elixir"},
            "content" => [t("x = 1")]
          },
          %{"type" => "mathBlock", "attrs" => %{"latex" => "e^{i\\pi} + 1 = 0"}},
          %{"type" => "videoEmbed", "attrs" => %{"provider" => "youtube", "id" => "dQw4w9WgXcQ"}},
          %{"type" => "horizontalRule"}
        ])

      out = clean!(input)
      assert length(out["content"]) == 7
      assert %{"type" => "heading", "attrs" => %{"level" => 2}} = hd(out["content"])
    end

    test "descarta lo desconocido: bloques, marcas, atributos y enlaces peligrosos" do
      out =
        clean!(
          doc([
            %{"type" => "script", "content" => [t("alert(1)")]},
            %{
              "type" => "heading",
              "attrs" => %{"level" => 1, "onclick" => "x"},
              "content" => [t("T")]
            },
            p([
              t("a", [%{"type" => "link", "attrs" => %{"href" => "javascript:alert(1)"}}]),
              t("b", [%{"type" => "link", "attrs" => %{"href" => "https://amauta.test/x"}}]),
              t("c", [%{"type" => "font", "attrs" => %{"color" => "red"}}])
            ]),
            %{"type" => "videoEmbed", "attrs" => %{"provider" => "evil", "id" => "x"}},
            %{
              "type" => "videoEmbed",
              "attrs" => %{"provider" => "youtube", "id" => "\"><script>"}
            },
            %{
              "type" => "codeBlock",
              "attrs" => %{"language" => "x\" onload=\"y"},
              "content" => [t("z")]
            }
          ])
        )

      assert [heading, paragraph, code] = out["content"]

      assert heading == %{
               "type" => "heading",
               "attrs" => %{"level" => 2},
               "content" => [%{"type" => "text", "text" => "T"}]
             }

      assert [
               %{"text" => "a"},
               %{"text" => "b", "marks" => [%{"attrs" => %{"href" => "https://amauta.test/x"}}]},
               %{"text" => "c"}
             ] =
               paragraph["content"]

      refute Map.has_key?(hd(paragraph["content"]), "marks")
      assert code["attrs"]["language"] == nil
    end

    test "acepta el JSON como texto y rechaza lo que no es un documento" do
      json = Jason.encode!(doc([p([t("hola")])]))
      assert {:ok, %{"type" => "doc"}} = RichText.sanitize(json)
      assert {:error, :invalid} = RichText.sanitize("<p>hola</p>")
      assert {:error, :invalid} = RichText.sanitize(%{"type" => "paragraph"})
      assert {:ok, nil} = RichText.sanitize("")
    end

    test "limita el tamaño y la profundidad" do
      huge = doc(for _ <- 1..6_000, do: p([t("x")]))
      assert {:error, :too_large} = RichText.sanitize(huge)

      deep =
        Enum.reduce(1..20, p([t("x")]), fn _, inner ->
          %{"type" => "blockquote", "content" => [inner]}
        end)

      assert {:error, :too_large} = RichText.sanitize(doc([deep]))
    end
  end

  describe "HTML" do
    test "escapa el texto y arma los bloques" do
      out =
        doc([
          p([t("<b>x</b> & y")]),
          %{"type" => "callout", "attrs" => %{"tone" => "info"}, "content" => [p([t("Nota")])]},
          %{
            "type" => "codeBlock",
            "attrs" => %{"language" => "python"},
            "content" => [t("if a < b:")]
          },
          %{"type" => "mathBlock", "attrs" => %{"latex" => "a<b \"c\""}},
          %{"type" => "videoEmbed", "attrs" => %{"provider" => "vimeo", "id" => "123456"}},
          p([t("web", [%{"type" => "link", "attrs" => %{"href" => "https://amauta.test"}}])])
        ])
        |> clean!()
        |> html()

      assert out =~ "<p>&lt;b&gt;x&lt;/b&gt; &amp; y</p>"
      assert out =~ ~s(<aside class="rich-callout" data-tone="info"><p>Nota</p></aside>)
      assert out =~ ~s(<pre><code class="language-python">if a &lt; b:</code></pre>)
      assert out =~ ~s(data-latex="a&lt;b &quot;c&quot;")
      assert out =~ ~s(src="https://player.vimeo.com/video/123456")

      assert out =~
               ~s(<a href="https://amauta.test" rel="noopener noreferrer nofollow" target="_blank">web</a>)

      refute out =~ "<b>"
    end
  end

  test "texto plano para la búsqueda" do
    text =
      doc([
        %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [t("Variables")]},
        p([t("Una "), t("variable", [%{"type" => "bold"}])]),
        %{
          "type" => "bulletList",
          "content" => [%{"type" => "listItem", "content" => [p([t("int")])]}]
        }
      ])
      |> clean!()
      |> RichText.to_text()

    assert text == "Variables\nUna variable\nint"
  end

  describe "tipo de Ecto" do
    test "depura al castear y guarda nil si no hay contenido" do
      assert {:ok, %{"type" => "doc"}} = Document.cast(Jason.encode!(doc([p([t("hola")])])))
      assert {:ok, nil} = Document.cast(Jason.encode!(RichText.empty()))
      assert :error = Document.cast("no es json")
      assert {:ok, nil} = Document.cast(nil)
    end

    test "un texto plano se convierte en párrafos" do
      assert %{"content" => [_, _]} = RichText.from_text("Uno\n\nDos")
    end
  end
end
