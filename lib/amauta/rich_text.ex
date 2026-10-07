defmodule Amauta.RichText do
  @moduledoc """
  Contenido enriquecido del editor de bloques (RF-CON-003, ERS 8.13).

  Se guarda el documento estructurado que produce el editor (JSON de
  Tiptap/ProseMirror), nunca HTML libre. Este módulo:

    * `sanitize/1`: lo depura con una lista blanca de bloques, marcas y
      atributos, y con límites de tamaño. Lo desconocido se descarta.
    * `to_html/1`: genera el HTML en el servidor, con el texto escapado.
      Las fórmulas (LaTeX) y el resaltado de código se completan en el
      navegador (KaTeX y highlight.js); sin JavaScript, se ve el LaTeX y
      el código tal cual.
    * `to_text/1`: el texto plano, para la búsqueda.

  Bloques del MVP: párrafo, títulos (2 a 4), listas, cita, recuadro
  destacado, código, fórmula, separador y video incrustado. Las imágenes y
  los archivos llegan con el contenido del curso; tablas, desplegables y
  listas de verificación, en V1.
  """

  @type document :: map()

  @max_nodes 5_000
  @max_depth 12
  @max_text 200_000

  @headings [2, 3, 4]
  @tones ~w(info warning success)
  @marks ~w(bold italic strike underline code link)

  # Proveedores de video: el iframe se arma acá, a partir del identificador.
  @video_providers %{
    "youtube" => {~r/^[A-Za-z0-9_-]{6,20}$/, "https://www.youtube-nocookie.com/embed/"},
    "vimeo" => {~r/^[0-9]{3,15}$/, "https://player.vimeo.com/video/"}
  }

  @doc "Documento vacío."
  def empty, do: %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}

  @doc "Documento con un único párrafo de texto (para migrar texto plano)."
  def from_text(nil), do: nil
  def from_text(""), do: nil

  def from_text(text) when is_binary(text) do
    paragraphs =
      text
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map(&%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => &1}]})

    %{"type" => "doc", "content" => paragraphs}
  end

  @doc "Indica si el documento no tiene texto ni bloques con contenido."
  def blank?(nil), do: true
  def blank?(doc), do: String.trim(to_text(doc)) == "" and not has_embeds?(doc)

  defp has_embeds?(%{"type" => type}) when type in ~w(mathBlock videoEmbed horizontalRule),
    do: true

  defp has_embeds?(%{"content" => content}) when is_list(content),
    do: Enum.any?(content, &has_embeds?/1)

  defp has_embeds?(_node), do: false

  @doc "Proveedores de video permitidos."
  def video_providers, do: Map.keys(@video_providers)

  ## Depuración

  @doc """
  Depura un documento. Devuelve `{:ok, documento}` o `{:error, motivo}`
  (`:invalid` si no es un documento, `:too_large` si excede los límites).
  Acepta el JSON como mapa o como texto.
  """
  @spec sanitize(term()) :: {:ok, document() | nil} | {:error, :invalid | :too_large}
  def sanitize(nil), do: {:ok, nil}
  def sanitize(""), do: {:ok, nil}

  def sanitize(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, doc} -> sanitize(doc)
      {:error, _} -> {:error, :invalid}
    end
  end

  def sanitize(%{"type" => "doc"} = doc) do
    {content, stats} = blocks(doc["content"], 1, %{nodes: 0, text: 0})

    cond do
      stats.nodes > @max_nodes or stats.text > @max_text -> {:error, :too_large}
      content == [] -> {:ok, empty()}
      true -> {:ok, %{"type" => "doc", "content" => content}}
    end
  catch
    :too_deep -> {:error, :too_large}
  end

  def sanitize(_other), do: {:error, :invalid}

  defp blocks(nodes, depth, stats) when is_list(nodes) do
    if depth > @max_depth, do: throw(:too_deep)

    Enum.flat_map_reduce(nodes, stats, fn node, stats ->
      case block(node, depth, %{stats | nodes: stats.nodes + 1}) do
        {nil, stats} -> {[], stats}
        {node, stats} -> {[node], stats}
      end
    end)
  end

  defp blocks(_nodes, _depth, stats), do: {[], stats}

  defp block(%{"type" => "paragraph"} = node, _depth, stats) do
    {content, stats} = inline(node["content"], stats)
    {with_content(%{"type" => "paragraph"}, content), stats}
  end

  defp block(%{"type" => "heading"} = node, _depth, stats) do
    level = get_in(node, ["attrs", "level"])
    level = if level in @headings, do: level, else: 2
    {content, stats} = inline(node["content"], stats)
    {with_content(%{"type" => "heading", "attrs" => %{"level" => level}}, content), stats}
  end

  defp block(%{"type" => type} = node, depth, stats)
       when type in ~w(blockquote bulletList orderedList listItem) do
    {content, stats} = blocks(node["content"], depth + 1, stats)

    if content == [] do
      {nil, stats}
    else
      attrs = if type == "orderedList", do: %{"start" => list_start(node)}, else: nil
      {%{"type" => type, "content" => content} |> put_attrs(attrs), stats}
    end
  end

  defp block(%{"type" => "callout"} = node, depth, stats) do
    tone = get_in(node, ["attrs", "tone"])
    tone = if tone in @tones, do: tone, else: "info"
    {content, stats} = blocks(node["content"], depth + 1, stats)
    content = if content == [], do: [%{"type" => "paragraph"}], else: content
    {%{"type" => "callout", "attrs" => %{"tone" => tone}, "content" => content}, stats}
  end

  defp block(%{"type" => "codeBlock"} = node, _depth, stats) do
    language = get_in(node, ["attrs", "language"])

    language =
      if is_binary(language) and language =~ ~r/^[a-z0-9+#-]{1,20}$/, do: language

    text = node |> Map.get("content", []) |> plain_text()
    stats = %{stats | text: stats.text + byte_size(text)}
    code = %{"type" => "codeBlock", "attrs" => %{"language" => language}}

    {with_content(code, if(text == "", do: [], else: [%{"type" => "text", "text" => text}])),
     stats}
  end

  defp block(%{"type" => "mathBlock"} = node, _depth, stats) do
    latex = get_in(node, ["attrs", "latex"])
    latex = if is_binary(latex), do: String.slice(latex, 0, 2_000), else: ""

    {%{"type" => "mathBlock", "attrs" => %{"latex" => latex}},
     %{stats | text: stats.text + byte_size(latex)}}
  end

  defp block(%{"type" => "videoEmbed"} = node, _depth, stats) do
    provider = get_in(node, ["attrs", "provider"])
    id = get_in(node, ["attrs", "id"])

    case @video_providers[provider] do
      {pattern, _url} when is_binary(id) ->
        if id =~ pattern,
          do:
            {%{"type" => "videoEmbed", "attrs" => %{"provider" => provider, "id" => id}}, stats},
          else: {nil, stats}

      _ ->
        {nil, stats}
    end
  end

  defp block(%{"type" => "horizontalRule"}, _depth, stats),
    do: {%{"type" => "horizontalRule"}, stats}

  defp block(_unknown, _depth, stats), do: {nil, stats}

  defp list_start(node) do
    case get_in(node, ["attrs", "start"]) do
      n when is_integer(n) and n > 0 and n < 100_000 -> n
      _ -> 1
    end
  end

  defp inline(nodes, stats) when is_list(nodes) do
    Enum.flat_map_reduce(nodes, stats, fn
      %{"type" => "text", "text" => text} = node, stats when is_binary(text) and text != "" ->
        marks = node |> Map.get("marks", []) |> marks()
        node = %{"type" => "text", "text" => text}
        node = if marks == [], do: node, else: Map.put(node, "marks", marks)
        {[node], %{stats | nodes: stats.nodes + 1, text: stats.text + byte_size(text)}}

      %{"type" => "hardBreak"}, stats ->
        {[%{"type" => "hardBreak"}], %{stats | nodes: stats.nodes + 1}}

      %{"type" => "mention", "attrs" => %{"id" => id, "label" => label}}, stats
      when is_binary(id) and is_binary(label) ->
        case Ecto.UUID.cast(id) do
          {:ok, id} ->
            label = label |> String.trim() |> String.slice(0, 120)

            {[%{"type" => "mention", "attrs" => %{"id" => id, "label" => label}}],
             %{stats | nodes: stats.nodes + 1}}

          :error ->
            {[], stats}
        end

      _other, stats ->
        {[], stats}
    end)
  end

  defp inline(_nodes, stats), do: {[], stats}

  defp marks(marks) when is_list(marks) do
    marks
    |> Enum.flat_map(fn
      %{"type" => "link"} = mark ->
        case safe_href(get_in(mark, ["attrs", "href"])) do
          nil -> []
          href -> [%{"type" => "link", "attrs" => %{"href" => href}}]
        end

      %{"type" => type} when type in @marks ->
        [%{"type" => type}]

      _ ->
        []
    end)
    |> Enum.uniq_by(& &1["type"])
  end

  defp marks(_marks), do: []

  @doc false
  def safe_href(href) when is_binary(href) do
    href = String.trim(href)

    case URI.parse(href) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        String.slice(href, 0, 2_000)

      %URI{scheme: "mailto", path: path} when is_binary(path) and path != "" ->
        String.slice(href, 0, 500)

      _ ->
        nil
    end
  end

  def safe_href(_href), do: nil

  defp with_content(node, []), do: node
  defp with_content(node, content), do: Map.put(node, "content", content)

  defp put_attrs(node, nil), do: node
  defp put_attrs(node, attrs), do: Map.put(node, "attrs", attrs)

  defp plain_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      %{"type" => "hardBreak"} -> "\n"
      _ -> ""
    end)
  end

  defp plain_text(_nodes), do: ""

  ## HTML

  @doc """
  HTML seguro del documento (ya depurado). Devuelve `Phoenix.HTML.safe()`.
  """
  def to_html(nil), do: {:safe, ""}

  def to_html(%{"type" => "doc", "content" => content}),
    do: {:safe, Enum.map(content, &html/1)}

  def to_html(_doc), do: {:safe, ""}

  defp html(%{"type" => "paragraph"} = node), do: ["<p>", children(node), "</p>"]

  defp html(%{"type" => "heading", "attrs" => %{"level" => level}} = node),
    do: ["<h#{level}>", children(node), "</h#{level}>"]

  defp html(%{"type" => "blockquote"} = node),
    do: ["<blockquote>", children(node), "</blockquote>"]

  defp html(%{"type" => "bulletList"} = node), do: ["<ul>", children(node), "</ul>"]

  defp html(%{"type" => "orderedList", "attrs" => %{"start" => start}} = node) do
    open = if start == 1, do: "<ol>", else: ~s(<ol start="#{start}">)
    [open, children(node), "</ol>"]
  end

  defp html(%{"type" => "listItem"} = node), do: ["<li>", children(node), "</li>"]

  defp html(%{"type" => "callout", "attrs" => %{"tone" => tone}} = node),
    do: [~s(<aside class="rich-callout" data-tone="#{tone}">), children(node), "</aside>"]

  defp html(%{"type" => "codeBlock", "attrs" => %{"language" => language}} = node) do
    class = if language, do: ~s( class="language-#{language}"), else: ""
    ["<pre><code", class, ">", children(node), "</code></pre>"]
  end

  defp html(%{"type" => "mathBlock", "attrs" => %{"latex" => latex}}) do
    escaped = escape(latex)
    [~s(<div class="rich-math" data-latex="), escaped, ~s(">), escaped, "</div>"]
  end

  defp html(%{"type" => "videoEmbed", "attrs" => %{"provider" => provider, "id" => id}}) do
    {_pattern, base} = @video_providers[provider]

    [
      ~s(<div class="rich-video"><iframe src="),
      base,
      id,
      ~s(" loading="lazy" allowfullscreen referrerpolicy="strict-origin-when-cross-origin" title="Video"></iframe></div>)
    ]
  end

  defp html(%{"type" => "horizontalRule"}), do: "<hr>"
  defp html(%{"type" => "hardBreak"}), do: "<br>"

  defp html(%{"type" => "mention", "attrs" => %{"id" => id, "label" => label}}),
    do: [~s(<span class="rich-mention" data-user-id="), id, ~s(">@), escape(label), "</span>"]

  defp html(%{"type" => "text", "text" => text} = node),
    do: node |> Map.get("marks", []) |> Enum.reduce(escape(text), &wrap_mark/2)

  defp html(_node), do: ""

  defp children(node), do: node |> Map.get("content", []) |> Enum.map(&html/1)

  defp wrap_mark(%{"type" => "bold"}, inner), do: ["<strong>", inner, "</strong>"]
  defp wrap_mark(%{"type" => "italic"}, inner), do: ["<em>", inner, "</em>"]
  defp wrap_mark(%{"type" => "strike"}, inner), do: ["<s>", inner, "</s>"]
  defp wrap_mark(%{"type" => "underline"}, inner), do: ["<u>", inner, "</u>"]
  defp wrap_mark(%{"type" => "code"}, inner), do: ["<code>", inner, "</code>"]

  defp wrap_mark(%{"type" => "link", "attrs" => %{"href" => href}}, inner),
    do: [
      ~s(<a href="),
      escape(href),
      ~s(" rel="noopener noreferrer nofollow" target="_blank">),
      inner,
      "</a>"
    ]

  defp wrap_mark(_mark, inner), do: inner

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  ## Menciones

  @doc "IDs de las personas mencionadas en el documento (sin repetir)."
  def mentions(nil), do: []

  def mentions(doc) do
    doc |> collect_mentions([]) |> Enum.reverse() |> Enum.uniq()
  end

  defp collect_mentions(%{"type" => "mention", "attrs" => %{"id" => id}}, acc), do: [id | acc]

  defp collect_mentions(%{"content" => content}, acc) when is_list(content),
    do: Enum.reduce(content, acc, &collect_mentions/2)

  defp collect_mentions(_node, acc), do: acc

  ## Texto plano

  @doc "Texto plano del documento, con un salto de línea entre bloques."
  def to_text(nil), do: ""

  def to_text(%{"content" => content}) when is_list(content) do
    content |> Enum.map(&text/1) |> Enum.reject(&(&1 == "")) |> Enum.join("\n")
  end

  def to_text(_doc), do: ""

  defp text(%{"type" => "text", "text" => text}), do: text
  defp text(%{"type" => "hardBreak"}), do: "\n"
  defp text(%{"type" => "mention", "attrs" => %{"label" => label}}), do: "@" <> label
  defp text(%{"type" => "mathBlock", "attrs" => %{"latex" => latex}}), do: latex

  defp text(%{"type" => type, "content" => content}) when type in ~w(paragraph heading codeBlock),
    do: Enum.map_join(content, &text/1)

  defp text(%{"content" => content}) when is_list(content),
    do: content |> Enum.map(&text/1) |> Enum.reject(&(&1 == "")) |> Enum.join("\n")

  defp text(_node), do: ""
end
