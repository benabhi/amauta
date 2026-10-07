// Editor de bloques (RF-CON-003), sobre Tiptap. Se carga bajo demanda desde
// el hook RichTextEditor (app.js). El documento vive en un input oculto del
// formulario como JSON: el servidor lo depura al guardar (Amauta.RichText).
import {Editor} from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import {Callout, MathBlock, VideoEmbed} from "./nodes"
import {SlashMenu} from "./slash_menu"
import {MentionPeople} from "./mention"
import {ensureKatexCss} from "./katex_css"

const readJSON = (text, fallback) => {
  try {
    return text ? JSON.parse(text) : fallback
  } catch (_error) {
    return fallback
  }
}

export const mountEditor = (root) => {
  ensureKatexCss()

  const input = root.querySelector("[data-editor-input]")
  const content = root.querySelector("[data-editor-content]")
  const linkPanel = root.querySelector("[data-link-panel]")
  const linkInput = root.querySelector("[data-link-input]")
  const labels = readJSON(root.dataset.labels, {})
  const commands = readJSON(root.dataset.commands, [])
  const people = readJSON(root.dataset.mentions, null)

  // Barra de herramientas: formato del texto, enlace y deshacer.
  const buttons = root.querySelectorAll("[data-command]")

  const refreshToolbar = (editor) => {
    for (const button of buttons) {
      const mark = button.dataset.mark
      if (mark) button.setAttribute("aria-pressed", String(editor.isActive(mark)))
    }
  }

  // El campo oculto se actualiza en el momento (si se guarda enseguida de
  // escribir, no se pierde nada); solo el aviso de cambio a LiveView espera.
  let timer
  const sync = (editor) => {
    input.value = JSON.stringify(editor.getJSON())
    clearTimeout(timer)
    timer = setTimeout(() => input.dispatchEvent(new Event("input", {bubbles: true})), 250)
  }

  const editor = new Editor({
    element: content,
    content: readJSON(input.value, null),
    extensions: [
      StarterKit.configure({
        heading: {levels: [2, 3, 4]},
        link: {openOnClick: false, autolink: true, protocols: ["mailto"], defaultProtocol: "https"},
      }),
      Placeholder.configure({placeholder: root.dataset.placeholder || ""}),
      Callout,
      MathBlock(labels),
      VideoEmbed(labels),
      SlashMenu(commands),
      ...(people ? [MentionPeople(people)] : []),
    ],
    editorProps: {
      attributes: {
        class: "rich-text rich-editor",
        role: "textbox",
        "aria-multiline": "true",
        "aria-labelledby": root.dataset.labelledby || "",
      },
    },
    onUpdate: ({editor}) => sync(editor),
    onTransaction: ({editor}) => refreshToolbar(editor),
  })

  content.dataset.slashLabel = labels.slash || ""

  const actions = {
    bold: () => editor.chain().focus().toggleBold().run(),
    italic: () => editor.chain().focus().toggleItalic().run(),
    strike: () => editor.chain().focus().toggleStrike().run(),
    code: () => editor.chain().focus().toggleCode().run(),
    undo: () => editor.chain().focus().undo().run(),
    redo: () => editor.chain().focus().redo().run(),
    link: () => {
      linkPanel.hidden = !linkPanel.hidden
      if (!linkPanel.hidden) {
        linkInput.value = editor.getAttributes("link").href || ""
        linkInput.focus()
      }
    },
  }

  for (const button of buttons) {
    button.addEventListener("click", () => actions[button.dataset.command]?.())
  }

  linkInput?.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      linkPanel.hidden = true
      editor.commands.focus()
    }
    if (event.key !== "Enter") return
    event.preventDefault()
    const href = linkInput.value.trim()
    const chain = editor.chain().focus().extendMarkRange("link")
    href ? chain.setLink({href}).run() : chain.unsetLink().run()
    linkPanel.hidden = true
  })

  refreshToolbar(editor)
  return editor
}
