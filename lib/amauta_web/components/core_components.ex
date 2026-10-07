defmodule AmautaWeb.CoreComponents do
  @moduledoc """
  Biblioteca de componentes de Amauta (ERS 6.5.7), sobre los tokens de
  `assets/css/app.css`. Toda la interfaz se arma con estos componentes: si
  falta uno, se agrega acá (con su historia en `storybook/`), no en la
  pantalla (RNF-MAN-007).

  Cada componente declara sus atributos y slots, contempla el modo oscuro y
  la accesibilidad (roles, etiquetas y foco), y usa propiedades lógicas de
  CSS (`ps`, `pe`, `ms`, `me`) para no atarse a la dirección del texto
  (RF-I18N-007).
  """
  use Phoenix.Component
  use Gettext, backend: AmautaWeb.Gettext

  alias Phoenix.LiveView.JS

  @families ~w(anil airampo chilca qolle cochinilla nogal)

  @doc "Familias de color pastel (ERS 6.5.2)."
  def families, do: @families

  ## Ícono

  @doc """
  Ícono del sprite de Phosphor (ERS 6.5.4). Los nombres disponibles están
  en `assets/icons.exs`; los de peso duotone llevan el sufijo `-duotone`.

  Sin `label` es decorativo (`aria-hidden`); con `label`, se anuncia.

      <.icon name="bell" />
      <.icon name="graduation-cap-duotone" class="size-16 text-anil-deep" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-5"
  attr :label, :string, default: nil

  def icon(assigns) do
    ~H"""
    <svg
      class={["inline-block shrink-0 fill-current", @class]}
      aria-hidden={is_nil(@label)}
      role={@label && "img"}
      aria-label={@label}
      focusable="false"
    >
      <use href={"/images/icons.svg##{@name}"} />
    </svg>
    """
  end

  ## Botones

  @doc """
  Botón. Con `href`, `navigate` o `patch` se dibuja como enlace.

      <.button>Guardar</.button>
      <.button variant="secondary" icon="plus">Nuevo</.button>
      <.button variant="danger" size="sm">Borrar</.button>
      <.button navigate={~p"/"} variant="ghost">Volver</.button>

  Variantes: `primary` (por defecto), `secondary`, `ghost` y `danger`.
  Mientras LiveView procesa el formulario, muestra un indicador de carga.
  """
  attr :variant, :string, default: "primary", values: ~w(primary secondary ghost danger)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :icon, :string, default: nil, doc: "ícono antes del texto"
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form target rel)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns = assign(assigns, :classes, button_classes(assigns))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={[@classes, @class]} {@rest}>
        <.icon :if={@icon} name={@icon} class={icon_size(@size)} />
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={[@classes, @class]} {@rest}>
        <.icon :if={@icon} name={@icon} class={[icon_size(@size), "phx-submit-loading:hidden"]} />
        <span class="hidden phx-submit-loading:inline-flex">
          <.spinner class={icon_size(@size)} />
        </span>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Botón de solo ícono. La etiqueta es obligatoria: es lo que anuncia el
  lector de pantalla y lo que muestra el tooltip.
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :variant, :string, default: "ghost", values: ~w(primary secondary ghost danger)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(href navigate patch method name value disabled type)

  def icon_button(assigns) do
    ~H"""
    <button
      class={[button_base(), variant_classes(@variant), square_size(@size), @class]}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <.icon name={@icon} class={icon_size(@size)} />
    </button>
    """
  end

  @doc """
  Editor de bloques (RF-CON-003) para un campo de formulario de tipo
  `Amauta.RichText.Document`. Al estilo Notion: se escribe y con «/» se
  elige el bloque (títulos, listas, cita, recuadro, código, fórmula, video,
  separador). El documento viaja como JSON en un input oculto y el servidor
  lo depura al guardar. El editor (Tiptap) se carga bajo demanda.

      <.rich_text_editor field={@form[:description]} label="Descripción" />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil

  attr :id, :string,
    default: nil,
    doc: "otro id vuelve a montar el editor (por ejemplo, vacío después de publicar)"

  attr :debounce, :string, default: nil, doc: "demora del aviso de cambio (phx-debounce)"

  attr :mentions, :list,
    default: nil,
    doc: "personas que se pueden mencionar con «@»: [%{id: id, label: nombre}]"

  def rich_text_editor(assigns) do
    %{field: field} = assigns

    value =
      case field.value do
        doc when is_map(doc) -> Jason.encode!(doc)
        json when is_binary(json) -> json
        _ -> ""
      end

    assigns =
      assign(assigns,
        id: assigns.id || "#{field.id}-editor",
        value: value,
        errors: Enum.map(field.errors, &translate_error/1),
        commands: Jason.encode!(rich_text_commands()),
        mention_list: assigns.mentions && Jason.encode!(assigns.mentions),
        labels:
          Jason.encode!(%{
            slash: gettext("Blocks"),
            math: gettext("LaTeX formula"),
            video: gettext("Video"),
            videoUrl: gettext("Video address"),
            videoHint: gettext("Paste a YouTube or Vimeo link and press Enter."),
            videoInvalid: gettext("That link is not from YouTube or Vimeo."),
            mentions: gettext("People")
          })
      )

    ~H"""
    <div class="mb-4">
      <span id={"#{@id}-label"} class="mb-1 block text-sm font-semibold">{@label}</span>
      <div
        id={@id}
        phx-hook="RichTextEditor"
        phx-update="ignore"
        data-commands={@commands}
        data-labels={@labels}
        data-labelledby={"#{@id}-label"}
        data-mentions={@mention_list}
        data-placeholder={@placeholder || gettext("Write, or type «/» to add a block…")}
        class="rounded-control border border-line bg-surface focus-within:border-primary"
      >
        <input
          type="hidden"
          name={@field.name}
          value={@value}
          phx-debounce={@debounce}
          data-editor-input
        />
        <div
          role="toolbar"
          aria-label={gettext("Text format")}
          class="flex flex-wrap items-center gap-0.5 border-b border-line p-1"
        >
          <.icon_button
            :for={
              {command, mark, icon, label} <- [
                {"bold", "bold", "text-b", gettext("Bold")},
                {"italic", "italic", "text-italic", gettext("Italic")},
                {"strike", "strike", "text-strikethrough", gettext("Strikethrough")},
                {"code", "code", "code", gettext("Inline code")},
                {"link", "link", "link", gettext("Link")}
              ]
            }
            type="button"
            icon={icon}
            label={label}
            size="sm"
            data-command={command}
            data-mark={mark}
            aria-pressed="false"
          />
          <span class="mx-1 h-5 w-px bg-line" aria-hidden="true" />
          <.icon_button
            type="button"
            icon="arrow-counter-clockwise"
            label={gettext("Undo")}
            size="sm"
            data-command="undo"
          />
          <.icon_button
            type="button"
            icon="arrow-clockwise"
            label={gettext("Redo")}
            size="sm"
            data-command="redo"
          />
        </div>
        <div data-link-panel hidden class="border-b border-line p-2">
          <input
            data-link-input
            type="url"
            placeholder="https://…"
            aria-label={gettext("Link address (Enter to apply, empty to remove)")}
            class="w-full rounded-control border border-line bg-surface px-3 py-1.5 text-sm"
          />
        </div>
        <div data-editor-content></div>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp rich_text_commands do
    [
      {"paragraph", gettext("Text")},
      {"heading2", gettext("Title")},
      {"heading3", gettext("Subtitle")},
      {"heading4", gettext("Small title")},
      {"bulletList", gettext("Bulleted list")},
      {"orderedList", gettext("Numbered list")},
      {"quote", gettext("Quote")},
      {"callout", gettext("Highlighted box")},
      {"calloutWarning", gettext("Warning box")},
      {"code", gettext("Code")},
      {"math", gettext("Formula (LaTeX)")},
      {"video", gettext("Video (YouTube or Vimeo)")},
      {"divider", gettext("Divider")}
    ]
    |> Enum.map(fn {id, label} -> %{id: id, label: label} end)
  end

  @doc """
  Contenido largo recortado a una altura máxima, con un desvanecido abajo y
  «Ver más» para desplegarlo. El botón aparece solo si el contenido de
  verdad no entra (lo mide el navegador, también cuando cargan imágenes o
  fórmulas).

      <.collapsible id="post-text-1"><.rich_text id="post-1" doc={@doc} /></.collapsible>
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def collapsible(assigns) do
    ~H"""
    <div id={@id} phx-hook=".Collapsible" class={["group/collapse", @class]}>
      <div
        id={"#{@id}-body"}
        data-collapse-body
        class="max-h-96 overflow-hidden group-data-overflow/collapse:mask-b-from-60% group-data-expanded/collapse:max-h-none"
      >
        {render_slot(@inner_block)}
      </div>
      <button
        type="button"
        data-collapse-toggle
        aria-expanded="false"
        aria-controls={"#{@id}-body"}
        class="mt-1 hidden min-h-11 group-data-overflow/collapse:inline-flex group-data-expanded/collapse:inline-flex items-center gap-1 text-sm font-semibold text-primary hover:underline"
      >
        <span class="group-data-expanded/collapse:hidden">{gettext("Show more")}</span>
        <span class="hidden group-data-expanded/collapse:inline">{gettext("Show less")}</span>
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Collapsible">
      // Mide si el contenido desborda; `this.js()` mantiene los atributos
      // aunque la vista se vuelva a dibujar.
      export default {
        mounted() {
          this.body = this.el.querySelector("[data-collapse-body]")
          this.button = this.el.querySelector("[data-collapse-toggle]")
          this.button.addEventListener("click", () => this.toggle())
          this.observer = new ResizeObserver(() => this.measure())
          for (const child of this.body.children) this.observer.observe(child)
          this.measure()
        },
        updated() { this.measure() },
        destroyed() { this.observer.disconnect() },
        measure() {
          if (this.expanded) return
          const js = this.js()
          // El botón se muestra por CSS cuando hay `data-overflow`.
          if (this.body.scrollHeight > this.body.clientHeight + 1) js.setAttribute(this.el, "data-overflow", "")
          else js.removeAttribute(this.el, "data-overflow")
        },
        toggle() {
          const js = this.js()
          const open = !this.expanded
          this.expanded = open
          js.setAttribute(this.button, "aria-expanded", String(open))
          // Desplegado no hay desvanecido; el botón sigue para «Ver menos».
          if (open) {
            js.removeAttribute(this.el, "data-overflow")
            js.setAttribute(this.el, "data-expanded", "")
          } else {
            js.removeAttribute(this.el, "data-expanded")
            js.setAttribute(this.el, "data-overflow", "")
            this.el.scrollIntoView({block: "nearest"})
          }
        }
      }
    </script>
    """
  end

  @doc """
  Archivos adjuntos con vista previa integrada (RF-TAB-005): las imágenes
  como miniaturas; imágenes, PDF y videos se abren en un diálogo sin salir
  de la página; el audio se escucha ahí mismo; el resto se descarga. Con
  `remove`, cada archivo tiene un botón para quitarlo (mientras se escribe).

      <.attachment_list id="post-1-files" files={@files} tenant={@current_scope} />
  """
  attr :id, :string, required: true
  attr :files, :list, required: true, doc: "archivos (`Amauta.Files.StoredFile`)"
  attr :tenant, :any, required: true, doc: "scope o institución, para las URLs"
  attr :remove, :string, default: nil, doc: "evento para quitar un archivo (recibe `id`)"
  attr :target, :any, default: nil
  attr :class, :any, default: nil

  def attachment_list(assigns) do
    {images, others} = Enum.split_with(assigns.files, &(preview_kind(&1) == :image))
    assigns = assign(assigns, images: images, others: others)

    ~H"""
    <div :if={@files != []} id={@id} phx-hook=".AttachmentPreview" class={["grid gap-2", @class]}>
      <ul :if={@images != []} class="flex flex-wrap gap-2" aria-label={gettext("Images")}>
        <li :for={file <- @images} class="flex items-start gap-1">
          <button
            type="button"
            data-preview="image"
            data-src={AmautaWeb.Paths.file(@tenant, file.id)}
            data-title={file.filename}
            class="block size-24 overflow-hidden rounded-control border border-line bg-surface-sunken focus-visible:outline-2 focus-visible:outline-primary sm:size-28"
            aria-label={gettext("View %{name}", name: file.filename)}
          >
            <img
              src={AmautaWeb.Paths.file(@tenant, file.id)}
              alt=""
              loading="lazy"
              class="size-full object-cover"
            />
          </button>
          <.attachment_remove :if={@remove} file={file} remove={@remove} target={@target} />
        </li>
      </ul>

      <ul :if={@others != []} class="grid gap-2" aria-label={gettext("Files")}>
        <li
          :for={file <- @others}
          class="flex min-h-14 items-center gap-3 rounded-control border border-line bg-surface px-3 py-2"
        >
          <.icon name={file_icon(file)} class="size-6 shrink-0 text-ink-muted" />
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold">{file.filename}</p>
            <p class="text-xs text-ink-muted">{AmautaWeb.Format.bytes(file.size)}</p>
            <audio
              :if={preview_kind(file) == :audio}
              controls
              preload="none"
              src={AmautaWeb.Paths.file(@tenant, file.id)}
              class="mt-1 w-full"
            />
          </div>
          <button
            :if={preview_kind(file) in [:pdf, :video]}
            type="button"
            data-preview={preview_kind(file)}
            data-src={AmautaWeb.Paths.file(@tenant, file.id)}
            data-title={file.filename}
            class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-control text-ink-muted hover:bg-surface-sunken hover:text-ink"
            aria-label={gettext("View %{name}", name: file.filename)}
          >
            <.icon name="eye" class="size-5" />
          </button>
          <a
            href={AmautaWeb.Paths.file_download(@tenant, file.id)}
            class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-control text-ink-muted hover:bg-surface-sunken hover:text-ink"
            aria-label={gettext("Download %{name}", name: file.filename)}
          >
            <.icon name="download-simple" class="size-5" />
          </a>
          <.attachment_remove :if={@remove} file={file} remove={@remove} target={@target} />
        </li>
      </ul>

      <dialog
        data-preview-dialog
        aria-label={gettext("Preview")}
        class="m-auto max-h-screen w-full max-w-4xl rounded-panel border border-line bg-surface p-0 text-ink shadow-lg backdrop:bg-ink/60"
      >
        <div class="flex items-center gap-2 border-b border-line px-4 py-2">
          <p data-preview-title class="min-w-0 flex-1 truncate text-sm font-semibold"></p>
          <button
            type="button"
            data-preview-close
            class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-control hover:bg-surface-sunken"
            aria-label={gettext("Close")}
          >
            <.icon name="x" class="size-5" />
          </button>
        </div>
        <div data-preview-body class="grid aspect-video w-full place-items-center bg-surface-sunken">
        </div>
      </dialog>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AttachmentPreview">
      // Vista previa en un diálogo nativo: atrapa el foco y se cierra con Esc.
      export default {
        mounted() {
          this.el.addEventListener("click", (e) => {
            const trigger = e.target.closest("[data-preview]")
            if (trigger) this.open(trigger)
            if (e.target.closest("[data-preview-close]")) this.dialog().close()
          })
        },
        dialog() {
          return this.el.querySelector("[data-preview-dialog]")
        },
        open(trigger) {
          const dialog = this.dialog()
          const body = dialog.querySelector("[data-preview-body]")
          const {preview: kind, src, title} = trigger.dataset
          dialog.querySelector("[data-preview-title]").textContent = title
          const tag = kind === "image" ? "img" : kind === "video" ? "video" : "iframe"
          const media = document.createElement(tag)
          media.className = "size-full object-contain"
          if (kind === "image") media.alt = title
          if (kind === "video") media.controls = true
          if (kind === "pdf") media.title = title
          media.src = src
          body.replaceChildren(media)
          dialog.addEventListener("close", () => body.replaceChildren(), {once: true})
          dialog.showModal()
        }
      }
    </script>
    """
  end

  attr :file, :map, required: true
  attr :remove, :string, required: true
  attr :target, :any, default: nil

  defp attachment_remove(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@remove}
      phx-value-id={@file.id}
      phx-target={@target}
      class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-control text-ink-muted hover:bg-surface-sunken hover:text-cochinilla-deep"
      aria-label={gettext("Remove %{name}", name: @file.filename)}
    >
      <.icon name="x" class="size-5" />
    </button>
    """
  end

  defp preview_kind(%{content_type: "image/" <> _}), do: :image
  defp preview_kind(%{content_type: "application/pdf"}), do: :pdf
  defp preview_kind(%{content_type: "video/" <> _}), do: :video
  defp preview_kind(%{content_type: "audio/" <> _}), do: :audio
  defp preview_kind(_file), do: :file

  defp file_icon(%{content_type: "application/pdf"}), do: "file-pdf"
  defp file_icon(%{content_type: "video/" <> _}), do: "file-video"
  defp file_icon(%{content_type: "audio/" <> _}), do: "file-audio"
  defp file_icon(%{content_type: "application/zip"}), do: "file-zip"
  defp file_icon(%{content_type: "text/" <> _}), do: "file-text"

  defp file_icon(%{content_type: type}) when is_binary(type) do
    cond do
      type =~ ~r/word|opendocument.text/ -> "file-doc"
      type =~ ~r/sheet|excel/ -> "file-xls"
      type =~ ~r/presentation|powerpoint/ -> "file-ppt"
      true -> "file"
    end
  end

  defp file_icon(_file), do: "file"

  @doc """
  Muestra contenido enriquecido ya depurado (`Amauta.RichText`): el HTML se
  genera en el servidor y el navegador completa fórmulas y código.

      <.rich_text id="pathway-description" doc={@pathway.description} />
  """
  attr :id, :string, required: true
  attr :doc, :map, default: nil
  attr :class, :any, default: nil

  def rich_text(assigns) do
    ~H"""
    <div :if={@doc} id={@id} phx-hook="RichContent" class={["rich-text", @class]}>
      {Amauta.RichText.to_html(@doc)}
    </div>
    """
  end

  @doc """
  Botón para copiar un texto al portapapeles (por ejemplo, un código de
  inscripción). Al copiar muestra un tilde por dos segundos y lo anuncia a
  los lectores de pantalla. El comportamiento está en `assets/js/app.js`
  (evento `amauta:copy`).

      <.copy_button value={@course.enrollment_code} />
  """
  attr :value, :string, required: true
  attr :label, :string, default: nil, doc: "por defecto, «Copiar»"
  attr :class, :any, default: nil
  attr :rest, :global

  def copy_button(assigns) do
    assigns = assign(assigns, :label, assigns.label || gettext("Copy"))

    ~H"""
    <button
      type="button"
      class={["group", button_base(), variant_classes("ghost"), square_size("sm"), @class]}
      data-copy={@value}
      data-copied-label={gettext("Copied")}
      phx-click={JS.dispatch("amauta:copy")}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <%!-- El span controla la visibilidad: el ícono trae su propio inline-block. --%>
      <span data-icon="copy" class="flex group-data-[copied]:hidden">
        <.icon name="copy" class="size-4" />
      </span>
      <span data-icon="copied" class="hidden group-data-[copied]:flex">
        <.icon name="check" class="size-4 text-chilca-deep" />
      </span>
      <span class="sr-only" aria-live="polite" data-copy-status></span>
    </button>
    """
  end

  defp button_classes(%{variant: variant, size: size}),
    do: [button_base(), variant_classes(variant), size_classes(size)]

  defp button_base do
    "inline-flex items-center justify-center gap-2 rounded-control font-semibold " <>
      "transition-[background-color,box-shadow,transform] duration-fast ease-standard " <>
      "active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none cursor-pointer " <>
      "phx-submit-loading:opacity-75"
  end

  defp variant_classes("primary"), do: "bg-primary text-on-primary shadow-sm hover:brightness-110"

  defp variant_classes("secondary"),
    do: "bg-surface text-ink border border-line shadow-sm hover:bg-surface-sunken"

  defp variant_classes("ghost"), do: "text-ink hover:bg-surface-sunken"

  defp variant_classes("danger"),
    do: "bg-cochinilla-soft text-cochinilla-deep hover:brightness-95"

  defp size_classes("sm"), do: "h-8 px-3 text-sm"
  defp size_classes("md"), do: "h-10 px-4 text-base"
  defp size_classes("lg"), do: "h-12 px-6 text-lg"

  defp square_size("sm"), do: "size-8"
  defp square_size("md"), do: "size-10"
  defp square_size("lg"), do: "size-12"

  defp icon_size("sm"), do: "size-4"
  defp icon_size("md"), do: "size-5"
  defp icon_size("lg"), do: "size-6"

  @doc "Indicador de carga."
  attr :class, :any, default: "size-5"

  def spinner(assigns) do
    ~H"""
    <.icon name="circle-notch" class={["motion-safe:animate-spin", @class]} />
    """
  end

  ## Insignias, avatares y detalles

  @doc """
  Insignia o chip con una familia de color pastel.

      <.badge family="chilca">Entregado</.badge>
  """
  attr :family, :string, default: "anil", values: ~w(anil airampo chilca qolle cochinilla nogal)
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex shrink-0 items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold",
      family_classes(@family),
      @class
    ]}>
      <.icon :if={@icon} name={@icon} class="size-3.5" />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp family_classes("anil"), do: "bg-anil-soft text-anil-deep"
  defp family_classes("airampo"), do: "bg-airampo-soft text-airampo-deep"
  defp family_classes("chilca"), do: "bg-chilca-soft text-chilca-deep"
  defp family_classes("qolle"), do: "bg-qolle-soft text-qolle-deep"
  defp family_classes("cochinilla"), do: "bg-cochinilla-soft text-cochinilla-deep"
  defp family_classes("nogal"), do: "bg-nogal-soft text-nogal-deep"

  @doc """
  Avatar con iniciales (o foto). El color sale del nombre, así cada persona
  conserva el suyo. La foto va encima de las iniciales: si no carga, quedan
  las iniciales (y no el texto alternativo cortado).
  """
  attr :name, :string, required: true
  attr :src, :string, default: nil
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :any, default: nil

  def avatar(assigns) do
    family = Enum.at(@families, :erlang.phash2(assigns.name, length(@families)))
    assigns = assign(assigns, initials: initials(assigns.name), family: family)

    ~H"""
    <span
      class={[
        "relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full font-semibold",
        avatar_size(@size),
        family_classes(@family),
        @class
      ]}
      title={@name}
    >
      <span aria-hidden="true">{@initials}</span>
      <span class="sr-only">{@name}</span>
      <img :if={@src} src={@src} alt="" class="absolute inset-0 size-full object-cover" />
    </span>
    """
  end

  defp avatar_size("sm"), do: "size-7 text-xs"
  defp avatar_size("md"), do: "size-9 text-sm"
  defp avatar_size("lg"), do: "size-14 text-lg"

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc "Tecla, para atajos de teclado."
  slot :inner_block, required: true

  def kbd(assigns) do
    ~H"""
    <kbd class="rounded-[4px] border border-line bg-surface-sunken px-1.5 py-0.5 font-mono text-xs text-ink-muted shadow-sm">
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  @doc "Separador, con un texto opcional en el medio."
  slot :inner_block

  def divider(assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-sm text-ink-muted" role="separator">
      <span class="h-px flex-1 bg-line" />
      <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
      <span :if={@inner_block != []} class="h-px flex-1 bg-line" />
    </div>
    """
  end

  ## Contenedores

  @doc "Tarjeta."
  attr :class, :any, default: nil
  attr :rest, :global
  slot :header
  slot :inner_block, required: true
  slot :footer

  def card(assigns) do
    ~H"""
    <section class={["rounded-card border border-line bg-surface shadow-sm", @class]} {@rest}>
      <header :if={@header != []} class="border-b border-line px-5 py-4 font-semibold">
        {render_slot(@header)}
      </header>
      <div class="px-5 py-4">{render_slot(@inner_block)}</div>
      <footer :if={@footer != []} class="border-t border-line px-5 py-3">
        {render_slot(@footer)}
      </footer>
    </section>
    """
  end

  @doc """
  Menú desplegable: un botón que abre una lista de acciones. Se cierra al
  tocar afuera o con Esc; el botón anuncia si está abierto.

      <.dropdown id="user-menu" label="Menú de la cuenta">
        <:trigger><.avatar name="Ana Pérez" size="sm" /></:trigger>
        <.dropdown_item navigate={~p"/unsur/settings"} icon="gear">Ajustes</.dropdown_item>
      </.dropdown>
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "nombre del botón para lectores de pantalla"
  slot :trigger, required: true
  slot :inner_block, required: true

  def dropdown(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative"
      phx-click-away={hide_dropdown(@id)}
      phx-window-keydown={hide_dropdown(@id)}
      phx-key="Escape"
    >
      <button
        id={"#{@id}-button"}
        type="button"
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-menu"}
        aria-label={@label}
        phx-click={toggle_dropdown(@id)}
        class="flex min-h-11 items-center gap-2 rounded-control px-1.5 hover:bg-surface-sunken"
      >
        {render_slot(@trigger)}
      </button>
      <div
        id={"#{@id}-menu"}
        role="menu"
        aria-labelledby={"#{@id}-button"}
        class="absolute end-0 z-50 mt-2 hidden w-64 rounded-panel border border-line bg-surface p-2 shadow-lg"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp toggle_dropdown(id) do
    JS.toggle(
      to: "##{id}-menu",
      in: {"ease-out duration-fast", "opacity-0 scale-95", "opacity-100 scale-100"},
      out: {"ease-in duration-instant", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-button")
  end

  defp hide_dropdown(id) do
    JS.hide(
      to: "##{id}-menu",
      transition: {"ease-in duration-instant", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-button")
  end

  @doc "Opción de un `dropdown/1`: un enlace (o un botón, sin destino)."
  attr :icon, :string, default: nil
  attr :rest, :global, include: ~w(href navigate patch method)
  slot :inner_block, required: true

  def dropdown_item(assigns) do
    ~H"""
    <.link
      role="menuitem"
      class="flex min-h-11 w-full items-center gap-3 rounded-control px-3 text-sm hover:bg-surface-sunken focus-visible:bg-surface-sunken"
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="size-4 text-ink-muted" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Indicador: un número grande con su etiqueta y, opcionalmente, un detalle.
  Si lleva `navigate`, toda la tarjeta es el enlace a lo que cuenta.

      <.stat value={128} label="Personas activas" icon="users" navigate={~p"/unsur/people"}>
        <:detail>12 con la invitación pendiente</:detail>
      </.stat>
  """
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :family, :string, default: "anil", values: ~w(anil airampo chilca qolle cochinilla nogal)
  attr :navigate, :string, default: nil
  attr :rest, :global
  slot :detail

  def stat(%{navigate: nil} = assigns) do
    ~H"""
    <div
      class="flex items-start gap-3 rounded-card border border-line bg-surface p-4 shadow-sm"
      {@rest}
    >
      <.stat_body {assigns} />
    </div>
    """
  end

  def stat(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-start gap-3 rounded-card border border-line bg-surface p-4 shadow-sm",
        "transition-transform duration-fast ease-standard hover:-translate-y-0.5",
        "focus-visible:-translate-y-0.5 motion-reduce:transition-none motion-reduce:hover:translate-y-0"
      ]}
      {@rest}
    >
      <.stat_body {assigns} />
    </.link>
    """
  end

  defp stat_body(assigns) do
    ~H"""
    <span
      :if={@icon}
      class={[
        "flex size-10 shrink-0 items-center justify-center rounded-control",
        family_classes(@family)
      ]}
    >
      <.icon name={@icon} class="size-5" />
    </span>
    <span class="min-w-0">
      <span class="block font-display text-2xl font-semibold leading-tight">{@value}</span>
      <span class="block text-sm text-ink-muted">{@label}</span>
      <span :if={@detail != []} class="mt-1 block text-xs text-ink-muted">
        {render_slot(@detail)}
      </span>
    </span>
    """
  end

  @doc """
  Tarjeta navegable, para grillas de trayectos y cursos: toda la tarjeta es
  el enlace. Se eleva apenas al pasar el puntero o con el foco.

      <.tile navigate={~p"/unsur/pathways/sistemas"} icon="path" title="Lic. en Sistemas">
        <:subtitle>LSI</:subtitle>
        <:badge><.badge>Publicado</.badge></:badge>
      </.tile>
  """
  attr :navigate, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true

  attr :family, :string,
    default: "airampo",
    values: ~w(anil airampo chilca qolle cochinilla nogal)

  attr :class, :any, default: nil
  attr :rest, :global
  slot :subtitle
  slot :badge

  def tile(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex h-full flex-col gap-2 rounded-card border border-line bg-surface p-5 shadow-sm",
        "transition-transform duration-fast ease-standard",
        "hover:-translate-y-0.5 focus-visible:-translate-y-0.5",
        "motion-reduce:transition-none motion-reduce:hover:translate-y-0",
        @class
      ]}
      {@rest}
    >
      <div class="flex items-start justify-between gap-3">
        <span class={[
          "flex size-10 shrink-0 items-center justify-center rounded-control",
          family_classes(@family)
        ]}>
          <.icon name={@icon} class="size-5" />
        </span>
        {render_slot(@badge)}
      </div>
      <p class="font-display text-lg font-semibold leading-snug">{@title}</p>
      <p :if={@subtitle != []} class="text-sm text-ink-muted">{render_slot(@subtitle)}</p>
    </.link>
    """
  end

  @doc """
  Pestañas de navegación (por ejemplo, las fijas del curso, ERS 4.3). Cada
  pestaña es un enlace con `patch`: cambia la URL sin recargar. En el
  celular se desliza de costado.

      <.tabs label="Curso">
        <:tab patch={~p"/unsur/c/prog1"} active>Tablón</:tab>
        <:tab patch={~p"/unsur/c/prog1/content"}>Contenido</:tab>
      </.tabs>
  """
  attr :label, :string, required: true, doc: "nombre de la navegación para lectores de pantalla"
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :patch, :string, required: true
    attr :active, :boolean
    attr :icon, :string
  end

  def tabs(assigns) do
    ~H"""
    <nav
      aria-label={@label}
      class={["overflow-x-auto overflow-y-hidden border-b border-line", @class]}
    >
      <ul class="flex min-w-max gap-1">
        <li :for={tab <- @tab}>
          <.link
            patch={tab.patch}
            aria-current={tab[:active] && "page"}
            class={[
              "-mb-px flex min-h-11 items-center gap-2 border-b-2 px-3 text-sm font-semibold",
              if(tab[:active],
                do: "border-primary text-ink",
                else: "border-transparent text-ink-muted hover:text-ink"
              )
            ]}
          >
            <.icon :if={tab[:icon]} name={tab.icon} class="size-4" />
            {render_slot(tab)}
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  @doc """
  Portada generativa de un curso (RF-CUR-001): un patrón de círculos y
  arcos que sale de una semilla (el ID del curso), así cada curso tiene la
  suya, siempre igual, sin guardar imágenes. Es decorativa: el nombre del
  curso va al lado, en texto.

      <.cover seed={@course.id} icon={@course.icon} family={@course.color} class="h-28" />
  """
  attr :seed, :string, required: true
  attr :icon, :string, default: nil
  attr :family, :string, default: "anil", values: ~w(anil airampo chilca qolle cochinilla nogal)
  attr :class, :any, default: nil

  def cover(assigns) do
    assigns = assign(assigns, :shapes, cover_shapes(assigns.seed))

    ~H"""
    <div
      class={["relative overflow-hidden rounded-card", family_classes(@family), @class]}
      aria-hidden="true"
    >
      <svg
        class="absolute inset-0 size-full"
        viewBox="0 0 400 120"
        preserveAspectRatio="xMidYMid slice"
        fill="none"
      >
        <circle
          :for={{x, y, r, filled} <- @shapes}
          cx={x}
          cy={y}
          r={r}
          class={if filled, do: "fill-current opacity-15", else: "stroke-current opacity-25"}
          stroke-width={if filled, do: 0, else: 6}
        />
      </svg>
      <span
        :if={@icon}
        class="absolute bottom-3 start-4 flex size-11 items-center justify-center rounded-control bg-surface/80 shadow-sm"
      >
        <.icon name={@icon} class="size-6" />
      </span>
    </div>
    """
  end

  # Seis formas deterministas a partir de la semilla.
  defp cover_shapes(seed) do
    for i <- 0..5 do
      h = :erlang.phash2({seed, i}, 1_000_000)
      x = rem(h, 400)
      y = rem(div(h, 400), 120)
      r = 18 + rem(div(h, 48_000), 70)
      {x, y, r, rem(i, 2) == 0}
    end
  end

  @doc """
  Estado vacío, con un ícono duotone y una acción opcional (ERS 6.5.4).
  """
  attr :icon, :string, default: "folder-open"
  attr :title, :string, required: true
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 rounded-panel border border-dashed border-line px-6 py-12 text-center">
      <.icon name={"#{@icon}-duotone"} class="size-14 text-anil-deep" />
      <p class="font-display text-lg font-semibold">{@title}</p>
      <p :if={@inner_block != []} class="max-w-prose text-ink-muted">{render_slot(@inner_block)}</p>
      <div :if={@action != []} class="mt-2">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc "Encabezado de página, con subtítulo y acciones."
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={["flex flex-wrap items-end justify-between gap-4 pb-6", @class]}>
      <div class="min-w-0">
        <h1 class="font-display text-2xl font-semibold leading-tight text-ink">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 text-ink-muted">{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  ## Avisos

  @doc """
  Aviso (toast) para los mensajes flash.

      <.flash kind={:info} flash={@flash} />
  """
  attr :id, :string, doc: "id opcional del aviso"
  attr :flash, :map, default: %{}, doc: "mensajes flash"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "tipo de aviso"
  attr :rest, :global
  slot :inner_block

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role={if @kind == :error, do: "alert", else: "status"}
      class="fixed end-4 top-4 z-50 w-80 max-w-[calc(100vw-2rem)] sm:w-96"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-card border p-4 shadow-lg",
        @kind == :info && "border-anil-deep/20 bg-anil-soft text-anil-deep",
        @kind == :error && "border-cochinilla-deep/20 bg-cochinilla-soft text-cochinilla-deep"
      ]}>
        <.icon :if={@kind == :info} name="info" class="mt-0.5 size-5" />
        <.icon :if={@kind == :error} name="warning-circle" class="mt-0.5 size-5" />
        <div class="min-w-0 flex-1 text-sm">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="group -m-1 cursor-pointer p-1" aria-label={gettext("close")}>
          <.icon name="x" class="size-4 opacity-60 group-hover:opacity-100" />
        </button>
      </div>
    </div>
    """
  end

  ## Formularios

  @doc """
  Campo de formulario con etiqueta, ayuda y errores. Con `field`, toma el
  nombre, el valor y los errores del formulario.

      <.input field={@form[:email]} type="email" label="Email" />
      <.input name="q" value="" placeholder="Buscar" />

  Tipos: los de HTML más `textarea`, `select` y `checkbox`.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :hint, :string, default: nil, doc: "texto de ayuda debajo del campo"
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField, doc: "campo del formulario, por ejemplo @form[:email]"
  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "si el checkbox está marcado"
  attr :prompt, :string, default: nil, doc: "primera opción vacía del select"
  attr :options, :list, doc: "opciones del select (Phoenix.HTML.Form.options_for_select/2)"
  attr :multiple, :boolean, default: false
  attr :class, :any, default: nil
  attr :inline, :boolean, default: false, doc: "etiqueta al costado y sin margen inferior"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step spellcheck)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-4">
      <label class="inline-flex cursor-pointer items-center gap-2">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={["size-4 rounded-[4px] border-line accent-primary", @class]}
          {@rest}
        />
        <span class="text-sm">{@label}</span>
      </label>
      <.field_errors errors={@errors} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-4">
      <.field_label for={@id} label={@label} />
      <select
        id={@id}
        name={@name}
        class={[field_classes(@errors), @class]}
        multiple={@multiple}
        aria-invalid={@errors != []}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.field_hint hint={@hint} />
      <.field_errors errors={@errors} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-4">
      <.field_label for={@id} label={@label} />
      <textarea
        id={@id}
        name={@name}
        class={[field_classes(@errors), "min-h-28 py-2", @class]}
        aria-invalid={@errors != []}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.field_hint hint={@hint} />
      <.field_errors errors={@errors} />
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={if @inline, do: "flex items-center gap-2", else: "mb-4"}>
      <.field_label for={@id} label={@label} inline={@inline} />
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[field_classes(@errors), @class]}
        aria-invalid={@errors != []}
        {@rest}
      />
      <.field_hint hint={@hint} />
      <.field_errors errors={@errors} />
    </div>
    """
  end

  defp field_classes(errors) do
    [
      "block w-full rounded-control border bg-surface-sunken px-3 h-10 text-ink",
      "placeholder:text-ink-muted/70 transition-[border-color,box-shadow] duration-fast",
      "focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30",
      "read-only:opacity-75",
      if(errors == [], do: "border-line", else: "border-cochinilla-deep")
    ]
  end

  attr :for, :any, default: nil
  attr :label, :string, default: nil
  attr :inline, :boolean, default: false

  defp field_label(assigns) do
    ~H"""
    <label
      :if={@label}
      for={@for}
      class={["text-sm font-semibold text-ink", if(@inline, do: "shrink-0", else: "mb-1.5 block")]}
    >
      {@label}
    </label>
    """
  end

  attr :hint, :string, default: nil

  defp field_hint(assigns) do
    ~H"""
    <p :if={@hint} class="mt-1.5 text-sm text-ink-muted">{@hint}</p>
    """
  end

  attr :errors, :list, default: []

  defp field_errors(assigns) do
    ~H"""
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  @doc "Mensaje de error de un campo."
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-sm text-cochinilla-deep">
      <.icon name="warning-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  ## Datos

  @doc """
  Tabla de datos.

      <.table id="people" rows={@people}>
        <:col :let={person} label="Nombre">{person.name}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "función que genera el id de cada fila"
  attr :row_click, :any, default: nil, doc: "función para el phx-click de cada fila"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "función que se aplica a cada fila antes de pasarla a los slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "acciones de cada fila, en la última columna"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto rounded-card border border-line bg-surface">
      <table class="w-full text-start text-sm">
        <thead class="border-b border-line bg-surface-sunken text-ink-muted">
          <tr>
            <th :for={col <- @col} class="px-4 py-2.5 text-start font-semibold">{col[:label]}</th>
            <th :if={@action != []} class="px-4 py-2.5">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="border-b border-line last:border-0 hover:bg-surface-sunken/60"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["px-4 py-3", @row_click && "cursor-pointer"]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 px-4 py-3 font-semibold">
              <div class="flex gap-3">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Lista de datos (término y valor).

      <.list>
        <:item title="Email">{@user.email}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-line">
      <div :for={item <- @item} class="grid gap-1 py-3 sm:grid-cols-3 sm:gap-4">
        <dt class="text-sm font-semibold text-ink-muted">{item.title}</dt>
        <dd class="sm:col-span-2">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  ## Comandos de JS

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 220,
      transition:
        {"transition-all ease-standard duration-base", "opacity-0 translate-y-2",
         "opacity-100 translate-y-0"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition:
        {"transition-all ease-in duration-fast", "opacity-100 translate-y-0",
         "opacity-0 translate-y-2"}
    )
  end

  @doc """
  Traduce un error de validación con el dominio `errors` de Gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(AmautaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(AmautaWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc "Traduce los errores de un campo."
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
