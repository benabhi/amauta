// Menú «/» del editor (RF-CON-003): al escribir «/» aparece la lista de
// bloques; se filtra escribiendo, se elige con ↑ ↓ y Enter, y Esc lo cierra.
// Las etiquetas vienen traducidas del servidor.
import {Extension} from "@tiptap/core"
import Suggestion from "@tiptap/suggestion"

const normalize = (text) =>
  text.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase()

// Qué hace cada bloque del menú.
export const runCommand = (editor, id) => {
  const chain = editor.chain().focus()
  switch (id) {
    case "paragraph": return chain.setParagraph().run()
    case "heading2": return chain.setHeading({level: 2}).run()
    case "heading3": return chain.setHeading({level: 3}).run()
    case "heading4": return chain.setHeading({level: 4}).run()
    case "bulletList": return chain.toggleBulletList().run()
    case "orderedList": return chain.toggleOrderedList().run()
    case "quote": return chain.toggleBlockquote().run()
    case "callout": return chain.wrapIn("callout", {tone: "info"}).run()
    case "calloutWarning": return chain.wrapIn("callout", {tone: "warning"}).run()
    case "code": return chain.setCodeBlock().run()
    case "math": return chain.insertContent({type: "mathBlock", attrs: {latex: ""}}).run()
    case "video": return chain.insertContent({type: "videoEmbed"}).run()
    case "divider": return chain.setHorizontalRule().run()
  }
}

const menu = () => {
  let root, list, items, active, command

  const render = () => {
    list.replaceChildren(
      ...items.map((item, index) => {
        const option = document.createElement("li")
        option.id = `rich-slash-${item.id}`
        option.role = "option"
        option.className = "rich-slash-item"
        option.setAttribute("aria-selected", String(index === active))
        option.textContent = item.label
        option.addEventListener("mousedown", (event) => {
          event.preventDefault()
          command(item)
        })
        return option
      }),
    )
    root.hidden = items.length === 0
  }

  const place = (rect) => {
    if (!rect) return
    root.style.left = `${rect.left + window.scrollX}px`
    root.style.top = `${rect.bottom + window.scrollY + 4}px`
  }

  return {
    onStart: (props) => {
      root = document.createElement("div")
      root.className = "rich-slash-menu"
      list = document.createElement("ul")
      list.role = "listbox"
      list.setAttribute("aria-label", props.editor.options.element.dataset.slashLabel || "")
      root.append(list)
      document.body.append(root)
      items = props.items
      active = 0
      command = props.command
      render()
      place(props.clientRect?.())
    },
    onUpdate: (props) => {
      items = props.items
      active = 0
      command = props.command
      render()
      place(props.clientRect?.())
    },
    onKeyDown: ({event}) => {
      if (items.length === 0) return false
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        const step = event.key === "ArrowDown" ? 1 : -1
        active = (active + step + items.length) % items.length
        render()
        return true
      }
      if (event.key === "Enter") {
        command(items[active])
        return true
      }
      if (event.key === "Escape") {
        root.hidden = true
        return true
      }
      return false
    },
    onExit: () => root?.remove(),
  }
}

export const SlashMenu = (commands) =>
  Extension.create({
    name: "slashMenu",

    addProseMirrorPlugins() {
      return [
        Suggestion({
          editor: this.editor,
          char: "/",
          items: ({query}) =>
            commands.filter((item) => normalize(item.label).includes(normalize(query))).slice(0, 12),
          command: ({editor, range, props}) => {
            editor.chain().focus().deleteRange(range).run()
            runCommand(editor, props.id)
          },
          render: menu,
        }),
      ]
    },
  })
