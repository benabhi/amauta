// Bloques propios del editor (RF-CON-003). Su JSON es el que depura el
// servidor (Amauta.RichText): si se agrega un bloque acá, se agrega allá.
import {Node, mergeAttributes} from "@tiptap/core"
import katex from "katex"

// Recuadro destacado: info, advertencia o éxito.
export const Callout = Node.create({
  name: "callout",
  group: "block",
  content: "block+",
  defining: true,

  addAttributes() {
    return {
      tone: {
        default: "info",
        parseHTML: (el) => el.dataset.tone || "info",
        renderHTML: (attrs) => ({"data-tone": attrs.tone}),
      },
    }
  },

  parseHTML() {
    return [{tag: "aside.rich-callout"}]
  },

  renderHTML({HTMLAttributes}) {
    return ["aside", mergeAttributes(HTMLAttributes, {class: "rich-callout"}), 0]
  },
})

// Fórmula LaTeX en bloque: se escribe arriba y se ve renderizada abajo.
export const MathBlock = (labels) =>
  Node.create({
    name: "mathBlock",
    group: "block",
    atom: true,
    selectable: true,

    addAttributes() {
      return {latex: {default: ""}}
    },

    parseHTML() {
      return [{tag: "div.rich-math", getAttrs: (el) => ({latex: el.dataset.latex || ""})}]
    },

    renderHTML({node}) {
      return ["div", {class: "rich-math", "data-latex": node.attrs.latex}, node.attrs.latex]
    },

    addNodeView() {
      return ({node, getPos, editor}) => {
        const dom = document.createElement("div")
        dom.className = "rich-math-edit"
        const input = document.createElement("textarea")
        input.rows = 2
        input.value = node.attrs.latex
        input.placeholder = "e^{i\\pi} + 1 = 0"
        input.setAttribute("aria-label", labels.math)
        const preview = document.createElement("div")
        preview.className = "rich-math-preview"
        preview.setAttribute("aria-hidden", "true")

        const render = (latex) =>
          katex.render(latex || "\\;", preview, {throwOnError: false, displayMode: true})

        render(node.attrs.latex)

        input.addEventListener("input", () => {
          render(input.value)
          const pos = getPos()
          if (typeof pos === "number") {
            editor.view.dispatch(editor.state.tr.setNodeMarkup(pos, undefined, {latex: input.value}))
          }
        })

        dom.append(input, preview)
        if (node.attrs.latex === "") requestAnimationFrame(() => input.focus())

        return {
          dom,
          stopEvent: (event) => event.target === input,
          ignoreMutation: () => true,
          update: (updated) => {
            if (updated.type.name !== "mathBlock") return false
            if (input.value !== updated.attrs.latex) {
              input.value = updated.attrs.latex
              render(updated.attrs.latex)
            }
            return true
          },
        }
      }
    },
  })

// Video incrustado: solo YouTube y Vimeo; el iframe lo arma el servidor a
// partir del proveedor y el identificador, nunca de una URL libre.
export const parseVideoUrl = (url) => {
  const text = (url || "").trim()
  const youtube = text.match(
    /^(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/)|youtu\.be\/)([A-Za-z0-9_-]{6,20})/,
  )
  if (youtube) return {provider: "youtube", id: youtube[1]}
  const vimeo = text.match(/^(?:https?:\/\/)?(?:www\.|player\.)?vimeo\.com\/(?:video\/)?(\d{3,15})/)
  if (vimeo) return {provider: "vimeo", id: vimeo[1]}
  return null
}

const embedUrl = ({provider, id}) =>
  provider === "youtube"
    ? `https://www.youtube-nocookie.com/embed/${id}`
    : `https://player.vimeo.com/video/${id}`

// Si el video se confirma al perder el foco por un clic (por ejemplo, en
// «Publicar»), el reproductor se muestra después de soltar: si apareciera
// antes, el bloque crecería, correría el botón y el clic se perdería.
let pointerDown = false
document.addEventListener("pointerdown", () => (pointerDown = true), true)
document.addEventListener("pointerup", () => (pointerDown = false), true)

const afterPointer = (fn) => {
  if (!pointerDown) return fn()
  document.addEventListener("pointerup", () => setTimeout(fn), {once: true, capture: true})
}

export const VideoEmbed = (labels) =>
  Node.create({
    name: "videoEmbed",
    group: "block",
    atom: true,
    selectable: true,

    addAttributes() {
      return {provider: {default: null}, id: {default: null}}
    },

    parseHTML() {
      return [{tag: "div[data-video-embed]"}]
    },

    renderHTML({node}) {
      return ["div", {"data-video-embed": "", "data-provider": node.attrs.provider, "data-id": node.attrs.id}]
    },

    addNodeView() {
      return ({node, getPos, editor}) => {
        const dom = document.createElement("div")
        dom.className = "rich-video-edit"

        const show = (attrs) => {
          dom.replaceChildren()
          if (attrs.provider && attrs.id) {
            const frame = document.createElement("div")
            frame.className = "rich-video"
            const iframe = document.createElement("iframe")
            iframe.src = embedUrl(attrs)
            iframe.title = labels.video
            iframe.loading = "lazy"
            iframe.allowFullscreen = true
            frame.append(iframe)
            dom.append(frame)
          } else {
            const input = document.createElement("input")
            input.type = "url"
            input.placeholder = "https://www.youtube.com/watch?v=…"
            input.setAttribute("aria-label", labels.videoUrl)
            const hint = document.createElement("p")
            hint.className = "rich-video-hint"
            hint.textContent = labels.videoHint
            // El enlace se toma sin esperar el Enter: al pegarlo, soltarlo o
            // autocompletarlo, y al salir del campo. Si no, al publicar el
            // bloque iría vacío y el servidor lo descartaría sin avisar. Lo
            // tipeado espera al Enter o al blur, para no tomar un ID a medias.
            let committed = false
            const commit = () => {
              if (committed) return true
              const parsed = parseVideoUrl(input.value)
              if (!parsed) return false
              committed = true
              const pos = getPos()
              if (typeof pos === "number") {
                editor.view.dispatch(editor.state.tr.setNodeMarkup(pos, undefined, parsed))
              }
              return true
            }
            const invalid = () => {
              hint.textContent = labels.videoInvalid
              hint.dataset.error = ""
            }
            input.addEventListener("input", (event) => {
              // Sin inputType: autocompletado del navegador.
              if (!event.inputType || /^insert(FromPaste|FromDrop|ReplacementText)/.test(event.inputType)) commit()
            })
            input.addEventListener("blur", () => {
              if (input.value.trim() !== "" && !commit()) invalid()
            })
            input.addEventListener("keydown", (event) => {
              if (event.key !== "Enter") return
              event.preventDefault()
              if (!commit()) invalid()
            })
            dom.append(input, hint)
            requestAnimationFrame(() => input.focus())
          }
        }

        show(node.attrs)

        return {
          dom,
          stopEvent: (event) => event.target.tagName === "INPUT",
          ignoreMutation: () => true,
          update: (updated) => {
            if (updated.type.name !== "videoEmbed") return false
            afterPointer(() => show(updated.attrs))
            return true
          },
        }
      }
    },
  })
